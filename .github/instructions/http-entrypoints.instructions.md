---
applyTo: "Modules/CIPPCore/Public/Entrypoints/HTTP Functions/**"
description: "Use when creating, modifying, or reviewing CIPP HTTP endpoint functions (Invoke-List*, Invoke-Exec*). Contains scaffold, RBAC metadata, parameter extraction, return conventions, error handling, scheduled tasks, and naming rules."
---

# CIPP HTTP Endpoint Functions

HTTP endpoint functions live in `Modules/CIPPCore/Public/Entrypoints/HTTP Functions/` organized by domain. They are auto-loaded by the CIPPCore module — no manifest changes needed.

## Routing

There is only **one** Azure Functions HTTP trigger. Requests flow through:

```
HTTP request → CIPPHttpTrigger → Receive-CippHttpTrigger
    → serializes Request for case-insensitivity
    → New-CippCoreRequest
        → resolves function: Invoke-{CIPPEndpoint}
        → runs RBAC checks (Test-CIPPAccess)
        → checks feature flags
        → invokes the handler
    → Receive-CippHttpTrigger does Push-OutputBinding
```

**Handlers return an `[HttpResponseContext]` — they do NOT call `Push-OutputBinding` themselves.** The outer trigger handles output binding and JSON serialization (`ConvertTo-Json -Depth 20 -Compress`).

## Naming

| Prefix | Purpose | HTTP Method |
|--------|---------|-------------|
| `Invoke-List*` | Read-only query | GET |
| `Invoke-Exec*` | Write / action | POST |
| `Invoke-Add*` | Create resource | POST |
| `Invoke-Edit*` | Update resource | POST |
| `Invoke-Remove*` | Delete resource | POST |

## When to create a new List* function

Only create a new `Invoke-List*` function when the endpoint needs **data transformation, enrichment, or multi-source aggregation** that can't be done on the frontend. If the endpoint is a straightforward pass-through to a single Graph/Exchange API, the frontend should use `Invoke-ListGraphRequest` instead — it accepts arbitrary Graph URIs and handles pagination, filtering, and response formatting generically.

Good reasons to create a dedicated List* function:
- Combining data from multiple API calls (e.g., users + licenses + sign-in activity)
- Transforming or computing derived properties before returning
- Filtering or joining with cached data (`New-CIPPDbRequest`)
- Calling Exchange/Teams cmdlets (not Graph URIs)
- Complex pagination or batching logic

If none of these apply, use `ListGraphRequest`.

## Scaffold

```powershell
function Invoke-ListExample {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Results = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/endpoint" -tenantid $TenantFilter -ErrorAction Stop
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }
}
```

```powershell
function Invoke-ExecExample {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID

    try {
        # Perform action
        $Result = "Successfully performed action for $UserID"
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message $Result -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Result = "Failed: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode ?? [HttpStatusCode]::OK
        Body       = @{ Results = $Result }
    }
}
```

Some Exec* functions handle multiple actions (add, edit, delete) via a switch on an action parameter rather than separate `Invoke-Add*` / `Invoke-Edit*` / `Invoke-Remove*` functions. Both approaches are in use — use whichever fits the endpoint. The switch pattern looks like:

```powershell
$Action = $Request.Body.Action ?? $Request.Query.Action
switch ($Action) {
    'Add'    { <# create logic #> }
    'Edit'   { <# update logic #> }
    'Delete' { <# remove logic #> }
    default  { $StatusCode = [HttpStatusCode]::BadRequest; $Result = "Unknown action: $Action" }
}
```

## RBAC metadata

Every function must declare `.FUNCTIONALITY` and `.ROLE` in comment-based help:

```powershell
<#
.FUNCTIONALITY
    Entrypoint
.ROLE
    Domain.Resource.Permission
#>
```

**`.FUNCTIONALITY`** values:
- `Entrypoint` — standard endpoint requiring a tenant context
- `Entrypoint,AnyTenant` — endpoint that works without a specific tenant (template CRUD, global settings)

**`.ROLE`** format: `Domain.Resource.Permission`

| Domain | Permissions |
|--------|-------------|
| `Identity` | `Read`, `ReadWrite` |
| `Exchange` | `Read`, `ReadWrite` |
| `Endpoint` | `Read`, `ReadWrite` |
| `Tenant` | `Read`, `ReadWrite` |
| `Security` | `Read`, `ReadWrite` |
| `Teams` | `Read`, `ReadWrite` |
| `CIPP` | `Read`, `ReadWrite` |

Resources vary by domain — check existing functions in the same domain folder for the correct resource name (e.g., `Identity.User`, `Exchange.Mailbox`).

## Parameter extraction

### Query-only (List* functions)

```powershell
$TenantFilter = $Request.Query.tenantFilter
$UserID = $Request.Query.UserID
```

### Null-coalescing Query ?? Body (Exec* functions — most common)

```powershell
$TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
$ID = $Request.Query.ID ?? $Request.Body.ID
```

### Body-only (complex write operations)

```powershell
$UserObj = $Request.Body
$Action = $Request.Body.Action
```

### Frontend autocomplete objects

The frontend sends autocomplete selections as `{ value: "id", label: "display", addedFields: { ... } }`. Extract the actual value:

```powershell
$TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
$UserUPNs = @($Request.Body.user | ForEach-Object { $_.addedFields.userPrincipalName ?? $_.value })
```

### Boolean coercion from query strings

```powershell
$MustChange = [System.Convert]::ToBoolean($Request.Query.MustChange ?? $Request.Body.MustChange)
```

## Common variables

| Variable | Set as | Purpose |
|----------|--------|---------|
| `$APIName` | `$Request.Params.CIPPEndpoint` | Passed to `Write-LogMessage -API` |
| `$Headers` | `$Request.Headers` | Passed to `Write-LogMessage -headers` for audit trail (who did it) |
| `$TenantFilter` | From query or body | The target tenant |

`$Headers` is only needed in write operations (Exec/Add/Edit/Remove) — read-only List* functions typically skip it.

## Return conventions

### List* functions — return array directly

```powershell
Body = @($Results)
```

### Exec* functions — return Results wrapper

```powershell
Body = @{ Results = "Successfully did X" }
# or for multiple messages:
Body = @{ Results = @($ResultMessages) }
```

### Structured results (multi-step operations)

```powershell
Body = @{
    Results = @(
        @{ resultText = 'Created user'; copyField = 'user@domain.com'; state = 'success' }
        @{ resultText = 'Failed to set license'; state = 'error' }
    )
}
```

## Status codes

| Code | When |
|------|------|
| `[HttpStatusCode]::OK` | Success (default) |
| `[HttpStatusCode]::BadRequest` | Missing required params, validation failure |
| `[HttpStatusCode]::InternalServerError` | Unhandled exception in catch block |

Use the `$StatusCode` fallback pattern — set the variable only in catch blocks:

```powershell
return [HttpResponseContext]@{
    StatusCode = $StatusCode ?? [HttpStatusCode]::OK
    Body       = $Body
}
```

### Early return for validation

```powershell
if (-not $RequiredParam) {
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = @{ Results = 'Error: RequiredParam is required' }
    }
}
```

## Error handling

Use `Get-CippException` (preferred) in catch blocks:

```powershell
catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers `
        -message "Failed to do X: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    $StatusCode = [HttpStatusCode]::InternalServerError
    $Body = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
}
```

### Bulk operations — per-item try/catch

Accumulate results for each item so one failure doesn't stop the batch:

```powershell
$Results = [System.Collections.Generic.List[object]]::new()
foreach ($Item in $Items) {
    try {
        # action
        $Results.Add("Successfully did X for $Item")
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Did X for $Item" -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results.Add("Failed for $Item: $($ErrorMessage.NormalizedError)")
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed for $Item: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
```

## Scheduled task delegation

When the frontend sends `Scheduled.Enabled = true`, defer the work to the scheduler instead of executing immediately:

```powershell
if ($Request.Body.Scheduled.Enabled) {
    $TaskBody = [pscustomobject]@{
        TenantFilter  = $TenantFilter
        Name          = "Description: $Details"
        Command       = @{ value = 'FunctionName'; label = 'FunctionName' }
        Parameters    = [pscustomobject]@{ Param1 = $Value1 }
        ScheduledTime = $Request.Body.Scheduled.date
        PostExecution = @{
            Webhook = [bool]$Request.Body.PostExecution.Webhook
            Email   = [bool]$Request.Body.PostExecution.Email
            PSA     = [bool]$Request.Body.PostExecution.PSA
        }
    }
    Add-CIPPScheduledTask -Task $TaskBody -hidden $false -Headers $Headers
    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = 'Successfully scheduled task' }
    }
}
# else: execute immediately
```

`Scheduled.date` is a Unix epoch timestamp. `PostExecution` controls notifications after task completion.

## Domain folder reference

See the domain folder table in `.github/copilot-instructions.md` for the full mapping. Place new functions in the folder matching their domain.
