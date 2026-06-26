# OpenAPI enrichment

`Add-OpenApiResponseSchemas.ps1` post-processes the generated CIPP `openapi.json`. It adds deterministic operationIds and typed `200` response schemas where response shape data can be derived from the CIPP frontend repository. It does not replace the upstream OpenAPI generator.

The enriched spec is published on each GitHub Release as the `openapi.enriched.json` release asset.

The PR check and release workflow strictly lint the CI-generated `openapi.enriched.json` with Redocly. The committed `.redocly.lint-ignore.yaml` baseline pins findings that already exist in the generated enriched spec because of upstream `openapi.json` issues. Any new Redocly error or warning that is not in the baseline fails CI.

To regenerate locally, check out the CIPP frontend repository and run:

```powershell
pwsh -NoProfile -File .build/Add-OpenApiResponseSchemas.ps1 `
  -FrontendRepoPath <path-to-CIPP-frontend-checkout> `
  -InputSpec ./openapi.json -OutputSpec ./openapi.enriched.json
```

If upstream `openapi.json` legitimately changes and the pinned Redocly findings must be refreshed, regenerate the enriched spec first, then regenerate the ignore baseline from that enriched output:

```powershell
pwsh -NoProfile -File .build/Add-OpenApiResponseSchemas.ps1 `
  -FrontendRepoPath <path-to-CIPP-frontend-checkout> `
  -InputSpec ./openapi.json -OutputSpec ./openapi.enriched.json
npx --yes @redocly/cli@2.35.1 lint ./openapi.enriched.json --generate-ignore-file
```

Do not generate the baseline from the base `openapi.json`. The lint subject is always the generated `openapi.enriched.json`.

## Known limitations

- Only `get`, `post`, `put`, `patch`, and `delete` operations are processed. `head`, `options`, and `trace` are not present in the current spec.
- Paths are assumed to start with `/api/`. All 580 current paths do.
- When a typed `200` response is added, it replaces the existing `200.content`. Today that content is only the generic `StandardResults` envelope.
- Conditional/ternary `simpleColumns` expressions are intentionally not parsed.

## Release workflow notes

- `openapi-enriched-release.yml` builds and uploads from the same tag. On `workflow_dispatch`, the `tag` input is checked out and used as the upload target. On `release: published`, the release tag is checked out and used as the upload target.
- `.github/workflows/` is gitignored in this repository, so the OpenAPI workflow files require `git add -f` when they are intentionally added or updated.
