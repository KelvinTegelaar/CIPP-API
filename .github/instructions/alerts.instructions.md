---
applyTo: "Modules/CIPPCore/Public/Alerts/**"
description: "Use when creating, modifying, or reviewing CIPP alert functions (Get-CIPPAlert*). Contains scaffolding patterns, parameter conventions, API call helpers, and output standards."
---

# CIPP Alert Functions

Alert functions live in `Modules/CIPPCore/Public/Alerts/` and are auto-loaded by the CIPPCore module. No manifest changes needed.

## Naming

- File: `Get-CIPPAlert<DescriptiveName>.ps1`
- Function name must match the filename exactly.

## Skeleton

Every alert follows this structure:

```powershell
function Get-CIPPAlert<Name> {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        # 1. (Optional) Parse $InputValue for configurable thresholds / allowlists
        # 2. (Optional) License gate via Test-CIPPStandardLicense
        # 3. Query data via New-GraphGetRequest / New-GraphBulkRequest / New-ExoRequest
        # 4. Filter results and build $AlertData as PSCustomObject array
        # 5. Write output

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-AlertMessage -message "<AlertName> alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    }
}
```

### Required elements

| Element | Rule |
|---------|------|
| `.FUNCTIONALITY Entrypoint` | Must be present in the comment-based help block — the scheduler uses this to discover the function. |
| `$InputValue` parameter | Always optional, aliased `input`. Carries user-configurable settings from the scheduler. |
| `$TenantFilter` parameter | The tenant identifier passed by the orchestrator. |
| `Write-AlertTrace` call | The **only** way to output results. Do not return data or write to output streams. |
| `try/catch` wrapper | All alert logic must be wrapped. Use `Get-CippException` (preferred) or `Get-NormalizedError` (legacy) in error messages. Log with `Write-AlertMessage`, not `Write-LogMessage`. |

## Parameters — `$InputValue` patterns

Alerts are configured in the UI. The orchestrator passes the config as `$InputValue`. Handle it defensively — it can be `$null`, a string, a number, a hashtable, or a PSCustomObject.

### Simple numeric threshold

```powershell
[int]$DaysThreshold = if ($InputValue) { [int]$InputValue } else { 30 }
```

### Object with named properties (preferred for new alerts)

```powershell
if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
    $DaysThreshold = if ($InputValue.ExpiringLicensesDays) { [int]$InputValue.ExpiringLicensesDays } else { 30 }
    $UnassignedOnly = if ($null -ne $InputValue.ExpiringLicensesUnassignedOnly) { [bool]$InputValue.ExpiringLicensesUnassignedOnly } else { $false }
} else {
    $DaysThreshold = if ($InputValue) { [int]$InputValue } else { 30 }
    $UnassignedOnly = $false
}
```

### Comma-separated allowlist

```powershell
$AllowedItems = @($InputValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
```

### JSON string that may need parsing

```powershell
if ($InputValue -is [string] -and $InputValue.Trim().StartsWith('{')) {
    try { $InputValue = $InputValue | ConvertFrom-Json -ErrorAction Stop } catch { }
}
```

## License gating

If the alert depends on a specific M365 capability (Intune, Exchange, Defender, etc.), gate it early with `Test-CIPPStandardLicense`. Never inspect raw SKU IDs manually.

```powershell
$Licensed = Test-CIPPStandardLicense -StandardName '<AlertName>' -TenantFilter $TenantFilter -Preset Intune
if (-not $Licensed) { return }
```

Use presets for common service families: `Exchange`, `SharePoint`, `Intune`, `Entra`, `EntraP2`, `Teams`, and `Compliance`. Use `-RequiredCapabilities` only when no preset matches, or combine it with `-Preset` when an alert needs a preset plus extra edge-case capabilities.

## Querying data

### Cached data (preferred)

Alerts should use cached tenant data from CIPPDB as their **primary data source** whenever possible. This avoids redundant live API calls for data that's already refreshed nightly. See `.github/instructions/cippdb.instructions.md` for available types and query patterns.

```powershell
$Users = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users'
$CAPolicies = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies'
```

Only make live API calls when the data isn't cached, or when freshness is critical. For scope selection, `-AsApp` usage, and available scopes when making live calls, see `.github/instructions/auth-model.instructions.md`.

### Single Graph call

```powershell
$Data = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/endpoint?`$filter=..." -tenantid $TenantFilter
```

### Bulk Graph calls (many items in parallel)

```powershell
$Requests = @($Items | ForEach-Object {
    @{
        id     = $_.id
        method = 'GET'
        url    = "/beta/servicePrincipals/$($_.id)/appRoleAssignments"
    }
})
$Responses = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -AsApp $true
```

Process bulk responses:

```powershell
foreach ($resp in $Responses) {
    if ([int]$resp.status -ne 200 -or -not $resp.body.value) { continue }
    # Process $resp.body.value
}
```

### Exchange Online

```powershell
$Results = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams @{ ... }
```

### Audit logs (time-windowed)

```powershell
$Since = (Get-Date).AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ')
$Logs = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $Since and ..." -tenantid $TenantFilter
```

## Building AlertData

AlertData is always an array of `PSCustomObject`. Every object should include a human-readable `Message` property.

```powershell
$AlertData = @($FilteredItems | ForEach-Object {
    [PSCustomObject]@{
        Message           = "User $($_.displayName) has not signed in for $InactiveDays days"
        DisplayName       = $_.displayName
        UserPrincipalName = $_.userPrincipalName
        Id                = $_.id
        Tenant            = $TenantFilter
    }
})
```

Include any fields that are useful for the alert notification — there is no fixed schema beyond `Message`, but be consistent with similar alerts.

## Writing results

Always use `Write-AlertTrace`. It handles:

- **Deduplication**: Compares new data to the last run's data (same day). Identical data is not re-stored.
- **Snooze filtering**: Removes snoozed alert items via `Remove-SnoozedAlerts` before comparison.
- **Storage**: Writes to the `AlertLastRun` Azure Table with RowKey `{TenantFilter}-{CmdletName}`.

```powershell
Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
```

### When to guard with `if`

When an alert **collects data into a variable first** (e.g. `$AlertData = foreach { ... }` or building up results in a loop), always wrap the trace call in a conditional:

```powershell
if ($AlertData) {
    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
```

This avoids writing empty traces for the common collect-then-write pattern. The guard is **not** required for ad-hoc / inline patterns where `Write-AlertTrace` is called directly inside the data-producing loop itself.

## Logging — `Write-AlertMessage` vs `Write-LogMessage`

Alert functions must use **`Write-AlertMessage`** for all logging — errors, warnings, and informational messages. `Write-AlertMessage` is a deduplication wrapper around `Write-LogMessage` that prevents the same message from being written multiple times in a single day for the same tenant. This is important because alert functions run repeatedly (every scheduler cycle) and would otherwise spam the `CippLogs` table with identical entries.

```powershell
# Write-AlertMessage signature
Write-AlertMessage -message 'Message text' -tenant $TenantFilter -tenantId $TenantId -LogData $ErrorMessage
```

`Write-AlertMessage` internally calls `Write-LogMessage` with `-sev 'Alert'` and `-API 'Alerts'` — you do not set those yourself.

**Do not use `Write-LogMessage` directly in alert functions.** Use `Write-LogMessage` in all other contexts (HTTP endpoints, standards, orchestrators, cache functions, etc.).

## Error handling

```powershell
catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-AlertMessage -message "Alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
}
```

Existing alerts may use the legacy `Get-NormalizedError` pattern or `Write-LogMessage` directly — that's fine for maintenance, but new alerts should use `Get-CippException` and `Write-AlertMessage`.

Some alerts intentionally swallow errors (e.g., APN cert check — most tenants don't have one). Use an empty catch block only when that's the correct behavior and add a comment explaining why.

For alerts that need to propagate errors to the orchestrator, rethrow after logging:

```powershell
catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-AlertMessage -message "Alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
    throw
}
```

## Registration

Alerts do not need manual registration. They are stored as **hidden scheduled tasks** in the `ScheduledTasks` Azure Table by the UI. The orchestrator discovers them by:

```powershell
$ScheduledTasks = Get-CIPPAzDataTableEntity @ScheduledTasks |
    Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' }
```

Each task row contains:

| Field | Value |
|-------|-------|
| `Command` | `Get-CIPPAlert<Name>` |
| `hidden` | `$true` |
| `Parameters` | JSON config (becomes `$InputValue`) |
| `Tenant` | Target tenant(s) |

The function is invoked dynamically — just drop the `.ps1` file in the Alerts folder and the module picks it up.

## Checklist for new alerts

1. Create `Modules/CIPPCore/Public/Alerts/Get-CIPPAlert<Name>.ps1`
2. Follow the skeleton exactly (`.FUNCTIONALITY Entrypoint`, param block, try/catch, Write-AlertTrace)
3. Add license gating if the data source requires a specific SKU
4. No changes needed to module manifests, timers, or registration code
