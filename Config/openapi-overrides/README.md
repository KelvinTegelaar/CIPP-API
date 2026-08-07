# OpenAPI overrides

`build/tools/build-openapi.ps1` derives `backend/Config/openapi.json` from the
PowerShell AST of every entrypoint under
`backend/Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions`. That covers the
overwhelming majority of the surface, because the AST preserves the whole member
chain — `$Request.Body.user.value` is recorded as an object with a `value`
property, not as a bare string.

A handful of endpoints still can't be read statically. Those get a file here.

## When you need one

Reach for an override only when the generator genuinely cannot see the contract:

- **The payload is reshaped by a cmdlet before it is read.** The generator follows
  `Where-Object`, `Sort-Object`, `Select-Object` and friends, which pass elements
  through unchanged. It stops at anything that transforms them — `Group-Object`,
  `Measure-Object` — because the result is a .NET type, not the request payload.
- **The fields are consumed inside a downstream helper.** If the entrypoint hands
  `$Request.Body` straight to `New-CIPPUserTask`, the fields live in that
  function, not in the entrypoint. These are emitted with
  `x-cipp-passthrough: true` and an open schema, which is honest but thin.
- **The field name is computed** (`$Request.Body.$Name`).

If instead the generator is missing a pattern that appears in several endpoints,
fix the generator — an override buys one endpoint, a pattern buys all of them.

## Format

One file per endpoint, named exactly after the endpoint: `ExecBulkLicense.json`
documents `/api/ExecBulkLicense`. Files beginning with `_` are ignored.

The JSON is deep-merged over the generated OpenAPI *operation object*, so you only
write the parts you are correcting:

- An object merges key by key, recursively.
- Any other value replaces what was generated.
- `null` deletes the key.
- The top-level `"method"` key is special: it overrides the inferred HTTP method
  and is removed before the merge.

Because it is a merge and not a replacement, everything you don't mention —
`x-cipp-role`, responses, tags — keeps coming from the source and stays current
as the source changes.

## Checking your work

```bash
pwsh build/tools/build-openapi.ps1 -Endpoint ExecBulkLicense
```

prints the resulting path object to stdout and writes nothing. When it looks
right, regenerate and commit the spec:

```bash
pwsh build/tools/build-openapi.ps1
```

## A caution

An override is a hand-maintained assertion about code that will change without
telling you. Keep them few, keep them small, and prefer teaching the generator.
