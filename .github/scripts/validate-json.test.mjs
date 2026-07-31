import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  formatAnnotation,
  publishResults,
  validateJson,
} from "./validate-json.mjs";

async function makeFixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "validate-json-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

async function runValidator(args, options) {
  const script = fileURLToPath(new URL("./validate-json.mjs", import.meta.url));
  const child = spawn(process.execPath, [script, ...args], options);
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8").on("data", (chunk) => (stdout += chunk));
  child.stderr.setEncoding("utf8").on("data", (chunk) => (stderr += chunk));
  const code = await new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("close", resolve);
  });
  return { code, stderr, stdout };
}

test("parses valid and BOM JSON and reports invalid JSON", async (t) => {
  const boundary = await makeFixture(t);
  const root = path.join(boundary, "Config");
  await mkdir(root);
  await writeFile(path.join(root, "valid.json"), '{"valid":true}');
  await writeFile(path.join(root, "bom.json"), '\uFEFF{"valid":true}');
  await writeFile(path.join(root, "invalid.json"), '{"invalid":}');

  const result = await validateJson({ boundary, roots: [root] });

  assert.equal(result.checked, 3);
  assert.equal(result.failures.length, 1);
  assert.match(result.failures[0].file, /invalid\.json$/);
  assert.match(result.failures[0].message, /JSON/);
});

test("skips only an optional missing root", async (t) => {
  const boundary = await makeFixture(t);

  const result = await validateJson({
    boundary,
    roots: [path.join(boundary, "missing")],
  });

  assert.deepEqual(result, { checked: 0, failures: [] });
});

test("rejects a root that is a file or symlink", async (t) => {
  const boundary = await makeFixture(t);
  const fileRoot = path.join(boundary, "file-root");
  const target = path.join(boundary, "target");
  const linkRoot = path.join(boundary, "link-root");
  await writeFile(fileRoot, "not a directory");
  await mkdir(target);
  await symlink(target, linkRoot, "dir");

  const result = await validateJson({ boundary, roots: [fileRoot, linkRoot] });

  assert.equal(result.checked, 0);
  assert.equal(result.failures.length, 2);
  assert.match(result.failures[0].message, /real directory/);
  assert.match(result.failures[1].message, /Symbolic links/);
});

test("rejects nested and JSON symlinks without reading outside the boundary", async (t) => {
  const boundary = await makeFixture(t);
  const outside = await makeFixture(t);
  const root = path.join(boundary, "Config");
  await mkdir(root);
  await writeFile(path.join(outside, "secret.json"), '{"secret":"do not read"}');
  await symlink(outside, path.join(root, "nested-link"), "dir");
  await symlink(
    path.join(outside, "secret.json"),
    path.join(root, "file-link.json"),
    "file",
  );

  const result = await validateJson({ boundary, roots: [root] });

  assert.equal(result.checked, 0);
  assert.equal(result.failures.length, 2);
  assert.ok(result.failures.every(({ message }) => /Symbolic links/.test(message)));
  assert.ok(result.failures.every(({ message }) => !message.includes("do not read")));
});

test("skips real node_modules directories but rejects a symlink with that name", async (t) => {
  const boundary = await makeFixture(t);
  const outside = await makeFixture(t);
  const skippedRoot = path.join(boundary, "skipped");
  const rejectedRoot = path.join(boundary, "rejected");
  await mkdir(path.join(skippedRoot, "node_modules"), { recursive: true });
  await writeFile(path.join(skippedRoot, "node_modules", "invalid.json"), "{");
  await mkdir(rejectedRoot);
  await symlink(outside, path.join(rejectedRoot, "node_modules"), "dir");

  const result = await validateJson({
    boundary,
    roots: [skippedRoot, rejectedRoot],
  });

  assert.equal(result.checked, 0);
  assert.equal(result.failures.length, 1);
  assert.match(result.failures[0].file, /node_modules$/);
  assert.match(result.failures[0].message, /Symbolic links/);
});

test("rejects roots outside the validation boundary", async (t) => {
  const boundary = await makeFixture(t);
  const outside = await makeFixture(t);

  const result = await validateJson({ boundary, roots: [outside] });

  assert.equal(result.checked, 0);
  assert.equal(result.failures.length, 1);
  assert.match(result.failures[0].message, /outside the validation boundary/);
});

test("escapes workflow-command data in annotations", () => {
  const annotation = formatAnnotation({
    file: "Config/bad%name,line:1\nnext.json",
    message: "bad%message\r\n::warning::spoof",
  });

  assert.equal(annotation.split("\n").length, 1);
  assert.match(annotation, /bad%25name%2Cline%3A1%0Anext\.json/);
  assert.match(annotation, /bad%25message%0D%0A::warning::spoof/);
});

test("publishes the atomic result before the numeric output", async (t) => {
  const directory = await makeFixture(t);
  const resultFile = path.join(directory, "results.json");
  const githubOutput = path.join(directory, "github-output");
  const failures = [{ file: "Config/bad.json", message: "invalid" }];

  await publishResults({ failures, resultFile, githubOutput });

  assert.deepEqual(JSON.parse(await readFile(resultFile, "utf8")), failures);
  assert.equal(await readFile(githubOutput, "utf8"), "invalid_count=1\n");
});

test("does not publish output when the atomic result write fails", async (t) => {
  const directory = await makeFixture(t);
  const resultFile = path.join(directory, "missing", "results.json");
  const githubOutput = path.join(directory, "github-output");

  await assert.rejects(
    publishResults({ failures: [], resultFile, githubOutput }),
    { code: "ENOENT" },
  );
  await assert.rejects(readFile(githubOutput, "utf8"), { code: "ENOENT" });
});

test("fails publication if output publication fails after the result write", async (t) => {
  const directory = await makeFixture(t);
  const resultFile = path.join(directory, "results.json");

  await assert.rejects(
    publishResults({ failures: [], resultFile, githubOutput: directory }),
    (error) => ["EISDIR", "EACCES"].includes(error.code),
  );
  assert.deepEqual(JSON.parse(await readFile(resultFile, "utf8")), []);
});

test("CLI publishes a numeric count but still fails its outcome for validation failures", async (t) => {
  const directory = await makeFixture(t);
  const root = path.join(directory, "Config");
  const githubOutput = path.join(directory, "github-output");
  await mkdir(root);
  await writeFile(path.join(root, "invalid.json"), "{");

  const result = await runValidator(
    ["--boundary", directory, root],
    {
      cwd: directory,
      env: { ...process.env, GITHUB_OUTPUT: githubOutput },
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  assert.equal(result.code, 1);
  assert.equal(result.stderr, "");
  assert.match(result.stdout, /::error file=.*invalid\.json::/);
  assert.equal(await readFile(githubOutput, "utf8"), "invalid_count=1\n");
  assert.equal(
    JSON.parse(await readFile(path.join(directory, "json-validation-results.json"), "utf8"))
      .length,
    1,
  );
});

test("workflow keeps the trusted tests, checkout opt-in, and fail-closed gate", async () => {
  const workflow = await readFile(
    new URL("../workflows/Validate_JSON.yml", import.meta.url),
    "utf8",
  );

  assert.match(workflow, /node --test \.github\/scripts\/validate-json\.test\.mjs/);
  assert.match(workflow, /allow-unsafe-pr-checkout: true/);
  assert.equal(workflow.match(/persist-credentials: false/g)?.length, 2);
  assert.match(workflow, /steps\.validate\.outcome != 'success'/);
  assert.match(workflow, /steps\.validate\.outputs\.invalid_count != '0'/);
  assert.match(workflow, /INVALID_COUNT: \$\{\{ steps\.validate\.outputs\.invalid_count \}\}/);
  assert.match(workflow, /\^\(0\|\[1-9\]\[0-9\]\*\)\$/);
  assert.match(workflow, /<code>\$\{present\(file\)\}<\/code>/);
  assert.match(workflow, /<code>\$\{present\(message\)\}<\/code>/);
  assert.doesNotMatch(workflow, /echo[^\n]*steps\.validate\.outputs\.invalid_count/);
});
