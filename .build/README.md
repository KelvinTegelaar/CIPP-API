# OpenAPI enrichment

`Add-OpenApiResponseSchemas.ps1` post-processes the generated CIPP `Config/openapi.json`. It normalizes the server URL to a deployment-origin variable, then adds deterministic operationIds and typed `200` response schemas where response shape data can be derived from the CIPP frontend repository. It does not replace the upstream OpenAPI generator.

The enrichment output defines one portable deployment-origin server and replaces any generated server list because CIPP's deployment-specific difference is the origin only. The spec keeps the fixed `/api/{Endpoint}` operation paths. Its server URL is `{origin}`, where `origin` is the CIPP deployment origin (scheme and host only, with no trailing slash or `/api` suffix). For example, setting `origin` to `https://tenant-api.azurewebsites.net` composes `/api/ListLogs` as `https://tenant-api.azurewebsites.net/api/ListLogs`. Function App, Static Web App, hosted, and custom-domain origins use the same input.

This is an intentional compatibility tradeoff: `{origin}` requires consumers to supply their CIPP deployment origin instead of relying on the same-origin resolution provided by the generated relative `/` server.

The enriched spec is published on each GitHub Release as the `openapi.enriched.json` release asset.

The PR check and release workflow strictly lint the CI-generated `openapi.enriched.json` with Redocly. The committed `.redocly.lint-ignore.yaml` baseline pins findings that already exist in the generated enriched spec because of upstream `openapi.json` issues. Any new Redocly error or warning that is not in the baseline fails CI.

To regenerate locally, check out the CIPP frontend repository and run:

```powershell
pwsh -NoProfile -File .build/Add-OpenApiResponseSchemas.ps1 `
  -FrontendRepoPath <path-to-CIPP-frontend-checkout> `
  -InputSpec ./Config/openapi.json -OutputSpec ./openapi.enriched.json
```

If upstream `openapi.json` legitimately changes and the pinned Redocly findings must be refreshed, regenerate the enriched spec first, then regenerate the ignore baseline from that enriched output:

```powershell
pwsh -NoProfile -File .build/Add-OpenApiResponseSchemas.ps1 `
  -FrontendRepoPath <path-to-CIPP-frontend-checkout> `
  -InputSpec ./Config/openapi.json -OutputSpec ./openapi.enriched.json
npx --yes @redocly/cli@2.35.1 lint ./openapi.enriched.json --generate-ignore-file
```

Do not generate the baseline from the base `Config/openapi.json`. The lint subject is always the generated `openapi.enriched.json`.

## Known limitations

- Only `get`, `post`, `put`, `patch`, and `delete` operations are processed. `head`, `options`, and `trace` are not present in the current spec.
- Paths are assumed to start with `/api/`. All current paths do.
- When a typed `200` response is added, it replaces the existing `200.content`. Today that content is only the generic `StandardResults` envelope.
- Conditional/ternary `simpleColumns` expressions are intentionally not parsed.
- `Config/openapi.json` is produced by an upstream generator. A future generator run could restore a relative `/` or `/api` server URL; the build test will flag the canonical regression, and the public enrichment stage independently normalizes its output back to `{origin}`.

## Release workflow notes

- `openapi-enriched-release.yml` builds and uploads from the same tag. On `workflow_dispatch`, the `tag` input is checked out and used as the upload target. On `release: published`, the release tag is checked out and used as the upload target.
- `.github/workflows/` is gitignored in this repository, so the OpenAPI workflow files require `git add -f` when they are intentionally added or updated.
