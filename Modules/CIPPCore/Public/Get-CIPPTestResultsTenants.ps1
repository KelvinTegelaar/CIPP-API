function Get-CIPPTestResultsTenants {
    <#
    .SYNOPSIS
        Retrieves CIPP test results across one, many, or all tenants with flexible filtering.

    .DESCRIPTION
        Queries the shared CippTestResults table server-side (partition / row / status / type /
        risk / category) so a single test can be compared across every tenant in one call. This is
        the cross-tenant counterpart to Get-CIPPTestResults (which is scoped to a single tenant).

        Custom test rows are enriched with their definition (Description / ReturnType /
        MarkdownTemplate) from the CustomPowershellScripts table so the off-canvas detail renders
        identically to the per-tenant dashboard. Every row is stamped with its tenant identity
        (Tenant / TenantId / TenantName) and a serialisable LastRun timestamp for display.

    .PARAMETER TenantFilter
        One or more tenant domains. Omit, or pass 'AllTenants' / 'allTenants', to query every tenant.

    .PARAMETER TestId
        One or more test IDs (the row's RowKey), e.g. 'CustomScript-<guid>'.

    .PARAMETER Status
        One or more statuses to filter on (Passed / Failed / Investigate / Skipped / Informational).

    .PARAMETER TestType
        Restrict to a single test type (Identity / Devices / Custom).

    .PARAMETER Risk
        Restrict to a single risk level (High / Medium / Low).

    .PARAMETER Category
        Restrict to a single category.

    .EXAMPLE
        Get-CIPPTestResultsTenants -TestId 'CustomScript-1234' -TestType 'Custom'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string[]]$TestId,

        [Parameter(Mandatory = $false)]
        [string[]]$Status,

        [Parameter(Mandatory = $false)]
        [string]$TestType,

        [Parameter(Mandatory = $false)]
        [string]$Risk,

        [Parameter(Mandatory = $false)]
        [string]$Category
    )

    $Table = Get-CippTable -tablename 'CippTestResults'

    # Build a single OData filter so all narrowing happens server-side. A cross-partition scan
    # (no PartitionKey clause) is acceptable here because it is always bounded by a RowKey/Status/
    # TestType clause when driven from the UI.
    $FilterParts = [System.Collections.Generic.List[string]]::new()

    $AllTenants = (-not $TenantFilter) -or ($TenantFilter -contains 'AllTenants') -or ($TenantFilter -contains 'allTenants')
    if (-not $AllTenants) {
        $TenantClause = (@($TenantFilter | Where-Object { $_ }) | ForEach-Object { "PartitionKey eq '$_'" }) -join ' or '
        if ($TenantClause) { $FilterParts.Add("($TenantClause)") }
    }
    if ($TestId) {
        $TestClause = (@($TestId | Where-Object { $_ }) | ForEach-Object { "RowKey eq '$_'" }) -join ' or '
        if ($TestClause) { $FilterParts.Add("($TestClause)") }
    }
    if ($Status) {
        $StatusClause = (@($Status | Where-Object { $_ }) | ForEach-Object { "Status eq '$_'" }) -join ' or '
        if ($StatusClause) { $FilterParts.Add("($StatusClause)") }
    }
    if ($TestType) { $FilterParts.Add("TestType eq '$TestType'") }
    if ($Risk) { $FilterParts.Add("Risk eq '$Risk'") }
    if ($Category) { $FilterParts.Add("Category eq '$Category'") }

    $Filter = $FilterParts -join ' and '

    $GetParams = @{}
    if ($Filter) { $GetParams.Filter = $Filter }
    $Results = @(Get-CIPPAzDataTableEntity @Table @GetParams)

    if ($Results.Count -eq 0) { return @() }

    # Map tenant domain (PartitionKey) -> tenant identity for display and access control.
    $TenantLookup = @{}
    try {
        foreach ($Tenant in (Get-Tenants -IncludeErrors)) {
            if ($Tenant.defaultDomainName) {
                $TenantLookup[$Tenant.defaultDomainName] = $Tenant
            }
        }
    } catch {
        Write-Warning "Get-CIPPTestResultsTenants: failed to load tenant list: $($_.Exception.Message)"
    }

    # Enrich Custom rows with their definition (latest version per ScriptGuid), mirroring the
    # per-tenant enrichment in Invoke-ListTests so the shared off-canvas renders identically.
    $CustomMeta = @{}
    if (@($Results | Where-Object { $_.TestType -eq 'Custom' }).Count -gt 0) {
        $ScriptTable = Get-CippTable -tablename 'CustomPowershellScripts'
        $Scripts = @(Get-CIPPAzDataTableEntity @ScriptTable -Filter "PartitionKey eq 'CustomScript'")
        $LatestByGuid = @{}
        foreach ($Script in $Scripts) {
            if (-not $Script.ScriptGuid) { continue }
            $Existing = $LatestByGuid[$Script.ScriptGuid]
            if (-not $Existing -or [int]$Script.Version -gt [int]$Existing.Version) {
                $LatestByGuid[$Script.ScriptGuid] = $Script
            }
        }
        foreach ($Script in $LatestByGuid.Values) {
            # Treat a missing Enabled property as enabled, matching Invoke-CIPPTestCollection.
            # A disabled (or deleted) script can still have stale results in the table; surfacing
            # this lets the UI show that the data no longer reflects an active test.
            $EnabledProp = $Script.PSObject.Properties['Enabled']
            $CustomMeta[$Script.ScriptGuid] = [PSCustomObject]@{
                ScriptName       = $Script.ScriptName ?? ''
                Description      = $Script.Description ?? ''
                ReturnType       = $Script.ReturnType ?? 'JSON'
                MarkdownTemplate = $Script.MarkdownTemplate ?? ''
                Enabled          = (-not $EnabledProp) -or [bool]$EnabledProp.Value
            }
        }
    }

    foreach ($Result in $Results) {
        $TenantInfo = $TenantLookup[$Result.PartitionKey]
        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Result.PartitionKey -Force
        $Result | Add-Member -NotePropertyName 'TenantId' -NotePropertyValue ($TenantInfo.customerId ?? '') -Force
        $Result | Add-Member -NotePropertyName 'TenantName' -NotePropertyValue ($TenantInfo.displayName ?? $Result.PartitionKey) -Force

        # Surface the Azure entity timestamp as a stable, serialisable last-run field.
        $LastRun = $Result.Timestamp
        if ($LastRun -is [DateTimeOffset]) {
            $LastRun = $LastRun.UtcDateTime.ToString('o')
        } elseif ($LastRun) {
            $LastRun = [string]$LastRun
        }
        $Result | Add-Member -NotePropertyName 'LastRun' -NotePropertyValue $LastRun -Force

        if ($Result.TestType -eq 'Custom') {
            $ScriptGuid = ($Result.RowKey -replace '^CustomScript-', '')
            if (-not [string]::IsNullOrWhiteSpace($ScriptGuid) -and $CustomMeta.ContainsKey($ScriptGuid)) {
                $Meta = $CustomMeta[$ScriptGuid]
                $Result | Add-Member -NotePropertyName 'Description' -NotePropertyValue $Meta.Description -Force
                $Result | Add-Member -NotePropertyName 'ReturnType' -NotePropertyValue $Meta.ReturnType -Force
                $Result | Add-Member -NotePropertyName 'MarkdownTemplate' -NotePropertyValue $Meta.MarkdownTemplate -Force
                $Result | Add-Member -NotePropertyName 'Enabled' -NotePropertyValue $Meta.Enabled -Force
                if ([string]::IsNullOrWhiteSpace($Result.Name) -and $Meta.ScriptName) {
                    $Result | Add-Member -NotePropertyName 'Name' -NotePropertyValue $Meta.ScriptName -Force
                }
            } else {
                # Result exists but the script no longer does (deleted). The data is stale — flag
                # it as not enabled so the column stays populated and truthful.
                $Result | Add-Member -NotePropertyName 'Enabled' -NotePropertyValue $false -Force
            }
        }
    }

    return $Results
}
