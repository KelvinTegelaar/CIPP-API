# CIPP-API Project Conventions

## Platform

- **Azure Functions** app running **PowerShell 7.4**
- Uses **Durable Functions** for orchestration (fan-out/fan-in, long-running workflows)
- All persistent data stored in **Azure Table Storage** (no SQL)
- Telemetry via **Application Insights** (optional)

## Project layout

```
├── Modules/                          # All PowerShell modules — bundled locally, not external
│   ├── CIPPCore/                     # Main module (~300+ exported functions)
│   │   ├── Public/                   # Exported functions (auto-loaded recursively)
│   │   ├── Private/                  # Internal-only functions
│   │   └── lib/                      # Binary dependencies (Cronos.dll, etc.)
│   ├── CippEntrypoints/             # HTTP/trigger router functions
│   ├── CippExtensions/              # Third-party integrations (Hudu, Halo, NinjaOne, etc.)
│   ├── AzBobbyTables/               # Azure Table Storage helper module
│   ├── DNSHealth/                   # DNS validation
│   ├── MicrosoftTeams/              # Teams API helpers
│   └── AzureFunctions.PowerShell.Durable.SDK/
├── CIPPHttpTrigger/                 # Single HTTP trigger → routes all API requests
├── CIPPOrchestrator/                # Durable orchestration trigger
├── CIPPActivityFunction/            # Durable activity trigger (parallelizable work)
├── CIPPQueueTrigger/                # Queue-based async processing
├── CIPPTimer/                       # Timer trigger (runs every 15 min)
├── Config/                          # JSON templates (CA, Intune, Transport Rules, BPA)
├── Tests/                           # Pester tests
├── profile.ps1                      # Module loading at startup
└── host.json                        # Azure Functions runtime config
```

## Module loading

Modules are **bundled in the repo**, not loaded from the PowerShell Gallery. `profile.ps1` imports them at startup in order: `CIPPCore` → `CippExtensions` → `AzBobbyTables`. The CIPPCore module auto-loads all functions under `Public/` recursively. No manifest changes are needed when adding new functions.

## How HTTP requests work

There is only **one** Azure Functions HTTP trigger (`CIPPHttpTrigger`). It routes all requests through `Receive-CippHttpTrigger` → `New-CippCoreRequest`, which:

1. Reads the `CIPPEndpoint` parameter from the route
2. Maps it to a function: `Invoke-{CIPPEndpoint}`
3. Validates RBAC permissions via `Test-CIPPAccess`
4. Checks feature flags
5. Invokes the handler function

**Only functions in `Modules/CIPPCore/Public/Entrypoints/HTTP Functions/` are callable by the frontend.** They are organized by domain:

| Folder | Domain |
|--------|--------|
| `CIPP/` | Platform administration |
| `Email-Exchange/` | Exchange Online |
| `Endpoint/` | Intune / device management |
| `Identity/` | Entra ID / users / groups |
| `Security/` | Defender / Conditional Access |
| `Teams-Sharepoint/` | Teams & SharePoint |
| `Tenant/` | Tenant-level settings |
| `Tools/` | Utility endpoints |

### HTTP function naming

- `Invoke-List*` — Read-only GET endpoints
- `Invoke-Exec*` — Write/action endpoints
- `Invoke-Add*` / `Invoke-Edit*` / `Invoke-Remove*` — CRUD variants

Full naming rules, scaffolds, return conventions, and RBAC metadata are in `.github/instructions/http-entrypoints.instructions.md`, auto-loaded when editing HTTP Functions.

## Durable Functions

The app uses durable orchestration for anything that takes more than a few seconds:

| Component | Purpose |
|-----------|---------|
| **Orchestrator** (`CIPPOrchestrator/`) | Coordinates multi-step workflows, fan-out/fan-in |
| **Activity** (`CIPPActivityFunction/`) | Individual work units invoked by orchestrators in parallel |
| **Queue** (`CIPPQueueTrigger/`) | Async task processing via `cippqueue` |
| **Timer** (`CIPPTimer/`) | Runs every 15 minutes, triggers scheduled orchestrators |

Orchestrator functions live in `Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/`.
Activity triggers live in `Modules/CIPPCore/Public/Entrypoints/Activity Triggers/`.
Timer functions live in `Modules/CIPPCore/Public/Entrypoints/Timer Functions/`.

## Key helper functions

Graph, Exchange, and Teams API helpers live in `Modules/CIPPCore/Public/GraphHelper/`. Key functions: `New-GraphGetRequest`, `New-GraphPOSTRequest`, `New-GraphBulkRequest`, `New-ExoRequest`, `New-ExoBulkRequest`, `New-TeamsRequest`. Full signatures and token details are in `.github/instructions/auth-model.instructions.md`.

### Table Storage

```powershell
$Table = Get-CIPPTable -tablename 'TableName'
$Entities = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'value'"
Add-CIPPAzDataTableEntity @Table -Entity $Row -Force   # Upsert
```

### Logging

```powershell
# General logging (HTTP endpoints, standards, orchestrators, cache, etc.)
Write-LogMessage -API 'EndpointName' -tenant $TenantFilter -message 'What happened' -sev Info

# Alert functions only — deduplicates by message + tenant per day
Write-AlertMessage -message 'Alert description' -tenant $TenantFilter -LogData $ErrorMessage
```

- **`Write-AlertMessage`**: Use exclusively in alert functions (`Get-CIPPAlert*`). It is a deduplication wrapper — checks if the same message was already logged today for the tenant, and only writes if new. Internally calls `Write-LogMessage` with `-sev 'Alert'` and `-API 'Alerts'`.
- **`Write-LogMessage`**: Use everywhere else. Directly writes to the `CippLogs` Azure Table with full audit context.

Severity levels: `Debug`, `Info`, `Warning`, `Error`. Logs go to the `CippLogs` Azure Table.

### Error handling

Use `Get-CippException -Exception $_` (preferred) or `Get-NormalizedError` (legacy) inside `catch` blocks, then `Write-LogMessage` with `-sev Error`. See `powershell-conventions.instructions.md` for full patterns.

## Tenant filtering

Every tenant-scoped operation receives a `$TenantFilter` parameter (domain name or GUID). Access is validated with `Test-CIPPAccess` at the HTTP layer. Always pass `$TenantFilter` (or `$Tenant` in standards) through to Graph/Exchange calls via `-tenantid`.

## Authentication model

CIPP is a **multi-tenant partner management tool**. A single **Secure Application Model (SAM)** app in the partner's tenant accesses all customer tenants via delegated admin (GDAP) or direct tenant relationships. Credentials live in Azure Key Vault; `Get-GraphToken` handles token acquisition, caching, and refresh automatically. Comprehensive documentation (SAM architecture, token flows, scopes, GDAP vs direct tenants, caching, API helpers) is in `.github/instructions/auth-model.instructions.md`, auto-loaded when editing GraphHelper files.

### What developers need to know

- **Never call `Get-GraphToken` directly** — `New-GraphGetRequest`, `New-ExoRequest`, etc. handle token acquisition internally
- **Always pass `-tenantid`** — without it, the call goes to the partner tenant, not the customer
- **Different scopes = different tokens**: Graph, Exchange, and Partner Center each have separate tokens
- **Do not hardcode secrets** — all credentials come from Key Vault via `Get-CIPPAuthentication`

## Function categories

| Category | Location | Naming | Purpose |
|----------|----------|--------|---------|
| HTTP endpoints | `Entrypoints/HTTP Functions/` | `Invoke-List*` / `Invoke-Exec*` | Frontend-callable API |
| Standards | `Standards/` | `Invoke-CIPPStandard*` | Compliance enforcement (remediate/alert/report) |
| Alerts | `Alerts/` | `Get-CIPPAlert*` | Tenant health monitoring |
| Orchestrators | `Entrypoints/Orchestrator Functions/` | `Start-*Orchestrator` | Workflow coordination |
| Activity triggers | `Entrypoints/Activity Triggers/` | `Push-*` | Parallelizable work units |
| Timer functions | `Entrypoints/Timer Functions/` | `Start-*` | Scheduled background jobs |
| DB cache | `Public/Set-CIPPDBCache*.ps1` | `Set-CIPPDBCache*` | Tenant data cache refresh |

## CIPP DB (tenant data cache)

CIPPDB is a **tenant-scoped read cache** backed by the `CippReportingDB` Azure Table. Standards, alerts, reports, and the UI read from cache instead of making live API calls. `Set-CIPPDBCache*` functions refresh the cache nightly; `New-CIPPDbRequest` is the primary reader. Comprehensive documentation (CRUD signatures, pipeline streaming, batch writes, collection grouping, scaffolding) is in `.github/instructions/cippdb.instructions.md`, auto-loaded when editing DB-related files.

## Coding conventions

Detailed PowerShell coding conventions are in `.github/instructions/powershell-conventions.instructions.md`, auto-loaded when editing `.ps1` files. Covers naming, collection building, pipeline usage, null handling, error handling, JSON serialization, and PS 7.4 idioms.

## Configuration

- **`host.json`** — Runtime config (timeouts, concurrency limits, extension bundles)
- **`CIPPTimers.json`** — Scheduled task definitions with priorities and cron expressions
- **`Config/`** — JSON templates for CA policies, Intune profiles, transport rules, BPA
- **Environment variables** — `AzureWebJobsStorage`, `APPLICATIONINSIGHTS_CONNECTION_STRING`, `CIPP_PROCESSOR`, `DebugMode`

## Things to avoid

- Do not install modules from the Gallery — bundle everything locally
- Do not modify module manifests to register new functions — auto-loading handles it
- Do not create new Azure Function trigger folders — use the existing five triggers
- Do not call `Write-Output` in HTTP functions — return an `[HttpResponseContext]` (the outer trigger handles `Push-OutputBinding`)
- Do not hardcode tenant IDs or secrets — use environment variables and `Get-GraphToken`
