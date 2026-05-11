---
applyTo: "**/*CIPPDb*.ps1,**/*CIPPDBCache*"
description: "Use when creating, modifying, or reviewing CIPP DB cache functions, OR when querying cached tenant data (New-CIPPDbRequest, Get-CIPPDbItem, Search-CIPPDbData) in standards, alerts, or HTTP endpoints. Covers the CippReportingDB table schema, CRUD function signatures, pipeline streaming, batch writes, collection grouping, cache types, and consumer patterns."
---

# CIPP DB — Tenant Data Cache

CIPPDB is a **tenant-scoped read cache** backed by the `CippReportingDB` Azure Table. It stores snapshots of Microsoft 365 data (users, groups, devices, policies, mailboxes, etc.) so that standards, alerts, reports, and the UI can query quickly without making live API calls.

## Architecture

```
Graph / Exchange / Intune APIs
        │
        ▼
  Set-CIPPDBCache*  (writer functions, one per data type)
        │  pipeline streaming, 500-item batch writes
        ▼
  CippReportingDB  (Azure Table Storage)
        │
        ▼
  New-CIPPDbRequest / Get-CIPPDbItem / Search-CIPPDbData  (readers)
        │
        ▼
  Standards, Alerts, HTTP endpoints, Reports  (consumers)
```

Cache refresh runs **nightly at 3:00 AM UTC** via `Start-CIPPDBCacheOrchestrator` (durable fan-out across all tenants). On-demand refresh available via the `Invoke-ExecCIPPDBCache` HTTP endpoint.

## Table schema

| Field | Value |
|-------|-------|
| `PartitionKey` | Tenant domain (e.g., `contoso.onmicrosoft.com`) |
| `RowKey` | `{Type}-{ItemId}` (e.g., `Users-john@contoso.com`) |
| `Data` | JSON-serialized object (the cached M365 data) |
| `Type` | Cache type name (e.g., `Users`, `Groups`, `ConditionalAccessPolicies`) |
| `DataCount` | Integer, only on `{Type}-Count` rows |

Each type has a `{Type}-Count` row (e.g., `Users-Count`) for fast aggregate counts without scanning all rows.

## Row key construction

**Formula**: `RowKey = "{Type}-{SanitizedItemId}"`

**ItemId extraction** (priority order from the pipeline object):
1. `ExternalDirectoryObjectId`
2. `id`
3. `Identity`
4. `skuId`
5. `userPrincipalName`
6. Random GUID (fallback)

**Sanitization**: `/\#?` → `_`, control characters (`\u0000-\u001F`, `\u007F-\u009F`) → removed. These are Azure Table disallowed characters.

## CRUD function reference

### Add-CIPPDbItem — Write / upsert

Accepts pipeline input for streaming writes. Two modes: **replace** (default — pre-deletes all existing rows for the type before writing) and **append** (adds alongside existing rows). Streams in 500-item batches. Can auto-record a `{Type}-Count` row after processing.

```powershell
# Stream from Graph API directly into cache (replace mode)
New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=..." -tenantid $TenantFilter |
    Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' -AddCount

# Append mode for historical/accumulating data
$NewAlerts | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AlertHistory' -Append -AddCount
```

### New-CIPPDbRequest — Read (deserialized)

**The most common reader.** Returns deserialized PowerShell objects (JSON → PSCustomObject). Auto-resolves tenant GUIDs to domain names.

```powershell
$Users = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users'
$CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
```

### Get-CIPPDbItem — Read (raw entities)

Returns raw Azure Table entities (hashtables). Supports filtering by tenant and type, or returning only `{Type}-Count` rows for fast aggregates.

```powershell
$Counts = Get-CIPPDbItem -TenantFilter $Tenant -CountsOnly
$RawEntities = Get-CIPPDbItem -TenantFilter $Tenant -Type 'Users'
```

### Update-CIPPDbItem — Partial or full update

Two mutually exclusive modes: full replacement (provide a complete object) or partial patch (provide only the properties to change).

```powershell
# Full replacement
Update-CIPPDbItem -TenantFilter $T -Type Users -ItemId $Id -InputObject $UpdatedUser

# Partial update — only change specific properties
Update-CIPPDbItem -TenantFilter $T -Type Users -ItemId $Id -PropertyUpdates @{
    displayName = 'New Name'
    enabled     = $false
}
```

### Remove-CIPPDbItem — Delete single item

Deletes a single cached item and auto-decrements the count row.

### Search-CIPPDbData — Regex full-text search

Searches raw JSON data across tenants and types. Supports OR (default) or AND matching, property-level filtering, and result caps. Two-pass: quick regex on raw JSON, then property-level verification when scoped to specific fields.

```powershell
Search-CIPPDbData -TenantFilter $Tenant -SearchTerms @('john', 'admin') -Types @('Users')
```

## Collection grouping system

`Invoke-CIPPDBCacheCollection` groups individual cache types into collection groups to reduce orchestrator activity count. Each collection runs as a single durable activity, calling its member `Set-CIPPDBCache*` functions sequentially. Check the function source for current groupings — they evolve as new types are added.

## Cache types

Available types are defined in `Config\CIPPDBCacheTypes.json`. Each type maps to a `Set-CIPPDBCache*` writer function. Check that file for the current type list — it covers identity, Exchange, security, Intune, compliance, and usage data.

## Writing a new Set-CIPPDBCache* function

### Scaffold

```powershell
function Set-CIPPDBCacheMyNewType {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantFilter,
        [Parameter()]
        [string[]]$Types
    )

    try {
        # 1. Optional license check
        $Licensed = Test-CIPPStandardLicense -StandardName 'MyFeature' -TenantFilter $TenantFilter -RequiredCapabilities @('REQUIRED_SKU')
        if (-not $Licensed) { return }

        # 2. Fetch data from API
        $Results = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/endpoint?`$top=999" -tenantid $TenantFilter -ErrorAction Stop

        # 3. Stream into cache
        $Results | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MyNewType' -AddCount
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache MyNewType: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
```

### Key patterns

- **Always use `-AddCount`** unless you handle count rows manually
- **Pipeline streaming** for large datasets: pipe directly from `New-GraphGetRequest` into `Add-CIPPDbItem`
- **License gating**: use `Test-CIPPStandardLicense` when the API requires specific SKUs
- **Conditional `$select`**: expand Graph `$select` fields based on license capabilities
- **Error handling**: catch, log with `Write-LogMessage`, do not rethrow (allows other types in the collection to continue)
- **No explicit return** of data — these functions write to the table as a side effect

### Exchange-based pattern

```powershell
# Exchange data requires New-ExoRequest instead of New-GraphGetRequest
$Mailboxes = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ ResultSize = 'Unlimited' } -ErrorAction Stop
$Mailboxes | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' -AddCount
```

### Registering a new type

1. Add the type name to `CIPPDBCacheTypes.json`
2. Add the type to the appropriate collection group in `Invoke-CIPPDBCacheCollection`
3. Create the `Set-CIPPDBCache{TypeName}.ps1` function in `Modules/CIPPCore/Public/`

## Consumer patterns

### In standards and alerts (most common)

```powershell
# Read cached data — no live API call needed
$CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

# Check freshness before using cache (optional, for critical operations)
$CacheInfo = Get-CIPPDbItem -TenantFilter $Tenant -Type 'ConditionalAccessPolicies' -CountsOnly
if ($CacheInfo.Timestamp -lt (Get-Date).AddHours(-3)) {
    Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $Tenant
}
$CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
```

### In HTTP endpoints

```powershell
# List available cached types for a tenant
$Counts = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly
$Types = $Counts | ForEach-Object { $_.RowKey -replace '-Count$', '' }

# Return deserialized data for a specific type
$Data = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Request.Query.Type
```

### Search across tenants

```powershell
# Find a user across all tenants
$Results = Search-CIPPDbData -SearchTerms @('john@contoso.com') -Types @('Users')

# Multi-term AND search within specific properties
$Results = Search-CIPPDbData -TenantFilter @('tenant1.onmicrosoft.com') -SearchTerms @('disabled', 'admin') -MatchAll -Properties @('displayName', 'accountEnabled')
```

## Important notes

- **Data staleness**: Cache is typically ~24 hours old (nightly refresh). Critical operations may need an on-demand refresh first.
- **Replace by default**: `Add-CIPPDbItem` deletes all existing rows for a type/tenant before writing new data. Use `-Append` only for accumulation scenarios.
- **Standards and alerts use cache as primary data source** — they rarely make live Graph calls for data that's already cached.
- **New-CIPPDbRequest vs Get-CIPPDbItem**: Use `New-CIPPDbRequest` when you need actual data (returns deserialized objects). Use `Get-CIPPDbItem` for metadata/counts or raw entity inspection.
- **Batch size**: The 500-item flush threshold is tuned for performance. Do not modify it.
- **GC behavior**: One `GC.Collect()` per batch flush. Aggressive GC was benchmarked and found slower.
