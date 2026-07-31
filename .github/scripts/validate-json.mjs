import { randomUUID } from "node:crypto";
import {
  appendFile,
  lstat,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

// Usage: node validate-json.mjs [--boundary <dir>] [--strip <prefix>] <dir> [dir...]
// --boundary confines all reads to a real directory. --strip removes a leading
// path prefix from reported filenames when a PR is checked out below the workspace.

const normalise = (value) => value.split(path.sep).join("/");

const report = (file, strip = "") => {
  const normalised = normalise(file);
  const normalisedStrip = normalise(strip);
  return normalisedStrip && normalised.startsWith(normalisedStrip)
    ? normalised.slice(normalisedStrip.length)
    : normalised;
};

const isWithin = (boundary, candidate) => {
  const relative = path.relative(boundary, candidate);
  return (
    relative === "" ||
    (!path.isAbsolute(relative) && relative !== ".." && !relative.startsWith(`..${path.sep}`))
  );
};

const structuralFailure = (file, message, strip) => ({
  file: report(file, strip),
  message,
});

async function getRequiredBoundary(boundary) {
  const absolute = path.resolve(boundary);
  const stats = await lstat(absolute);
  if (stats.isSymbolicLink() || !stats.isDirectory()) {
    throw new Error(`Validation boundary is not a real directory: ${normalise(absolute)}`);
  }
  return { absolute, real: await realpath(absolute) };
}

export async function validateJson({ boundary, roots, strip = "" }) {
  const allowed = await getRequiredBoundary(boundary);
  const failures = [];
  const files = [];

  async function collect(directory, displayDirectory) {
    const entries = await readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      const display = path.join(displayDirectory, entry.name);
      const stats = await lstat(full);

      if (stats.isSymbolicLink()) {
        failures.push(
          structuralFailure(display, "Symbolic links are not allowed in validation roots.", strip),
        );
        continue;
      }

      if (stats.isDirectory()) {
        const resolved = await realpath(full);
        if (!isWithin(allowed.real, resolved)) {
          failures.push(
            structuralFailure(display, "Path resolves outside the validation boundary.", strip),
          );
          continue;
        }
        if (entry.name === "node_modules") continue;
        await collect(full, display);
        continue;
      }

      if (stats.isFile()) {
        if (!entry.name.endsWith(".json")) continue;
        const resolved = await realpath(full);
        if (!isWithin(allowed.real, resolved)) {
          failures.push(
            structuralFailure(display, "Path resolves outside the validation boundary.", strip),
          );
          continue;
        }
        files.push({ full, display });
        continue;
      }

      failures.push(
        structuralFailure(display, "Unsupported filesystem entry type in validation root.", strip),
      );
    }
  }

  for (const root of roots) {
    const absoluteRoot = path.resolve(root);
    if (!isWithin(allowed.absolute, absoluteRoot)) {
      failures.push(
        structuralFailure(root, "Path is outside the validation boundary.", strip),
      );
      continue;
    }

    let stats;
    try {
      stats = await lstat(absoluteRoot);
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }

    if (stats.isSymbolicLink()) {
      failures.push(
        structuralFailure(root, "Symbolic links are not allowed as validation roots.", strip),
      );
      continue;
    }
    if (!stats.isDirectory()) {
      failures.push(
        structuralFailure(root, "Validation root must be a real directory.", strip),
      );
      continue;
    }

    const resolvedRoot = await realpath(absoluteRoot);
    if (!isWithin(allowed.real, resolvedRoot)) {
      failures.push(
        structuralFailure(root, "Path resolves outside the validation boundary.", strip),
      );
      continue;
    }
    await collect(absoluteRoot, root);
  }

  let checked = 0;
  for (const { full, display } of files) {
    checked++;
    // PowerShell's ConvertFrom-Json, which loads these files in CIPP, tolerates a BOM.
    const contents = (await readFile(full, "utf8")).replace(/^\uFEFF/, "");
    try {
      JSON.parse(contents);
    } catch (error) {
      failures.push({ file: report(display, strip), message: error.message });
    }
  }

  return { checked, failures };
}

const escapeCommandData = (value) =>
  String(value).replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");

const escapeCommandProperty = (value) =>
  escapeCommandData(value).replace(/:/g, "%3A").replace(/,/g, "%2C");

export function formatAnnotation({ file, message }) {
  return `::error file=${escapeCommandProperty(file)}::${escapeCommandData(message)}`;
}

export async function publishResults({
  failures,
  resultFile = path.resolve("json-validation-results.json"),
  githubOutput = process.env.GITHUB_OUTPUT,
}) {
  const absoluteResult = path.resolve(resultFile);
  const temporaryResult = path.join(
    path.dirname(absoluteResult),
    `.${path.basename(absoluteResult)}.${process.pid}.${randomUUID()}.tmp`,
  );

  try {
    await writeFile(temporaryResult, JSON.stringify(failures, null, 2), { flag: "wx" });
    await rename(temporaryResult, absoluteResult);
    if (githubOutput) {
      await appendFile(githubOutput, `invalid_count=${failures.length}\n`);
    }
  } finally {
    await rm(temporaryResult, { force: true }).catch(() => {});
  }
}

function parseArguments(argv) {
  let boundary = ".";
  let strip = "";
  const roots = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--boundary") {
      boundary = argv[++i] ?? "";
    } else if (argv[i] === "--strip") {
      strip = argv[++i] ?? "";
    } else {
      roots.push(argv[i]);
    }
  }
  return { boundary, roots, strip };
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArguments(argv);
  const { checked, failures } = await validateJson(options);

  for (const failure of failures) {
    console.log(formatAnnotation(failure));
  }
  console.log(`Checked ${checked} JSON file(s), ${failures.length} invalid.`);

  // Atomically publish the trusted result before exposing its numeric step output.
  await publishResults({ failures });
  return failures.length > 0 ? 1 : 0;
}

const isDirectInvocation =
  process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href;

if (isDirectInvocation) {
  try {
    process.exitCode = await main();
  } catch (error) {
    console.error("JSON validator failed before completing.");
    console.log(
      formatAnnotation({
        file: ".github/scripts/validate-json.mjs",
        message: error instanceof Error ? error.message : String(error),
      }),
    );
    process.exitCode = 1;
  }
}
