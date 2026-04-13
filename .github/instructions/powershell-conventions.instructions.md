---
applyTo: "**/*.ps1"
description: "Use when writing or reviewing PowerShell code in CIPP. Covers naming, collection building, pipeline usage, null handling, error handling, JSON serialization, and other PS 7.4 idioms."
---

# PowerShell Coding Conventions

## Naming

- **Variables**: Always `$PascalCase` — `$TenantFilter`, `$AlertData`, `$GraphRequest`. No camelCase or snake_case.
- **Functions**: Verb-Noun per PowerShell convention — `Get-CIPPAlert*`, `New-GraphGetRequest`, `Set-CIPPDBCache*`.
- **Parameters**: PascalCase, typed, with explicit `[Parameter(Mandatory = $true)]` or `$false`. Every public function uses `[CmdletBinding()]`.

## Collection building

Prefer `$Results = foreach` to collect output from loops — it's cleaner than `+=` and more readable than `.Add()`:

```powershell
# Preferred: assign foreach output directly
$Requests = foreach ($User in $Users) {
    @{
        id     = $User.id
        method = 'GET'
        url    = "/beta/users/$($User.id)"
    }
}
```

For performance-critical paths with large or streaming datasets, use `[System.Collections.Generic.List[T]]` with `.Add()`:

```powershell
$Findings = [System.Collections.Generic.List[object]]::new()
foreach ($item in $LargeDataset) {
    $Findings.Add([PSCustomObject]@{ ... })
}
```

Use `[System.Collections.Generic.HashSet[string]]` for deduplication and fast lookups:

```powershell
$SeenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if (-not $SeenKeys.Add($Key)) { continue }  # skip duplicates
```

Avoid `$array += $item` in loops — it copies the entire array on every iteration.

## Pipeline

Prefer pipeline for streaming data through transformations, especially for cache writes:

```powershell
New-GraphGetRequest -uri '...' -tenantid $TenantFilter |
    Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -AddCount
```

Use `foreach` loops when you need imperative logic (branching, multiple side effects, early exit).

## Null and empty checks

```powershell
if ($null -eq $InputObject) { return }       # null check — $null on the left
if (-not $var) { ... }                        # falsy check (null, empty, $false)
if ([string]::IsNullOrWhiteSpace($value)) {}  # only when whitespace matters
```

## Null-coalescing (`??`)

The codebase uses PowerShell 7.4 — lean on `??` for fallback values:

```powershell
$TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter ?? $env:TenantID
$DesiredValue = $Settings.SomeField.value ?? $Settings.SomeField
```

## Array forcing

Always wrap in `@()` when the result might be a single item or null but you need an array:

```powershell
$Items = @(New-GraphGetRequest -uri '...' -tenantid $TenantFilter)
foreach ($item in @($response.value)) { ... }
```

## Object creation

Always use `[PSCustomObject]@{}` — never `New-Object PSObject`. No PowerShell classes or enums.

```powershell
[PSCustomObject]@{
    DisplayName       = $User.displayName
    UserPrincipalName = $User.userPrincipalName
    Tenant            = $TenantFilter
}
```

## Strings

Use double-quoted interpolation. For Graph URIs, backtick-escape the `$` in OData parameters:

```powershell
$uri = "https://graph.microsoft.com/beta/users?`$top=999&`$select=$Select&`$filter=$Filter"
$message = "Added alias $Alias to $User"
```

## JSON serialization

Always specify `-Compress` and `-Depth`:

```powershell
$Body = @{ property = $Value } | ConvertTo-Json -Compress -Depth 10
$Parsed = $RawJson | ConvertFrom-Json -ErrorAction SilentlyContinue
```

## Splatting

Use hashtable splatting for functions with many parameters:

```powershell
$Table = Get-CIPPTable -tablename 'CippLogs'
Add-CIPPAzDataTableEntity @Table -Entity $Row -Force
```

## Suppressing unwanted output

Use `| Out-Null` for general cases. Use `[void]` when calling `.Add()` on generic lists:

```powershell
Add-CIPPAzDataTableEntity @Table -Entity $Row -Force | Out-Null
[void]$List.Add($Item)
```

## Logging — `Write-AlertMessage` vs `Write-LogMessage`

| Function | When to use |
|----------|-------------|
| `Write-AlertMessage` | **Alert functions only** (`Get-CIPPAlert*`). Deduplicates by message + tenant per day, then delegates to `Write-LogMessage` with `-sev 'Alert'` and `-API 'Alerts'`. |
| `Write-LogMessage` | **Everything else** — HTTP endpoints, standards, orchestrators, activity triggers, cache functions, timer functions. Directly writes to the `CippLogs` table with full audit context (user, IP, severity, API area). |

```powershell
# In alert functions — dedup wrapper, no -sev or -API needed
Write-AlertMessage -message 'Something failed' -tenant $TenantFilter -LogData $ErrorMessage

# Everywhere else — full logging with severity and API area
Write-LogMessage -API 'Standards' -tenant $TenantFilter -message 'Action completed.' -sev Info
Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
```

## Error handling

Always specify `-ErrorAction` — never rely on the default:

```powershell
Import-Module -Name $Path -Force -ErrorAction Stop         # critical: stop on failure
$help = Get-Help $cmd -ErrorAction SilentlyContinue         # optional: suppress expected errors
```

Wrap API calls in `try/catch` with `Get-CippException` (preferred) or `Get-NormalizedError` (legacy):

```powershell
# General code (HTTP endpoints, standards, cache, etc.)
try {
    $Result = New-GraphGetRequest -uri '...' -tenantid $TenantFilter
} catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-LogMessage -API 'Area' -tenant $TenantFilter -message "Failed: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
}

# Alert functions — use Write-AlertMessage instead
try {
    $Result = New-GraphGetRequest -uri '...' -tenantid $TenantFilter
} catch {
    $ErrorMessage = Get-CippException -Exception $_
    Write-AlertMessage -message "Alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
}
```

## Conditionals

Use `switch` for 3+ branches. Use `if`/`elseif` only for simple binary conditions:

```powershell
switch ($Property) {
    'delegatedAccessStatus' { ... }
    'availableLicense' { ... }
    default { return $null }
}
```

## Dates

Use `Get-Date` with explicit UTC conversion for storage/comparison:

```powershell
$Now = (Get-Date).ToUniversalTime()
$Threshold = (Get-Date).AddDays(-30)
$IsoTimestamp = [string]$(Get-Date $Now -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
```

## Return values

Use explicit `return` — do not rely on implicit output:

```powershell
return $Results
return $true
if (-not $Licensed) { return }
```
