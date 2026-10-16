function Get-CIPPReportPage {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Serves one page of a cached report as { Results, Metadata }.
    .DESCRIPTION
    AllTenants reads are paged by whole tenants: tenants holding rows of any -Type are walked in ordinal
    order and -Report runs once per tenant until the page covers at least -PageSize cached rows, so
    per-tenant processing in the report still sees all of that tenant's data. A single tenant is one
    page. Metadata.nextLink carries the last tenant served and is absent on the final page.
    .PARAMETER Report
    Runs once per tenant with the tenant domain as its only argument and emits that tenant's rows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string[]]$Type,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Report,
        [int]$PageSize,
        [string]$ContinuationToken
    )

    $Metadata = @{}
    if ($TenantFilter -ne 'AllTenants') {
        return [PSCustomObject]@{
            Results  = @(& $Report $TenantFilter)
            Metadata = $Metadata
        }
    }

    $PageSize = if ($PageSize -gt 0) { [Math]::Min([Math]::Max($PageSize, 250), 10000) } else { 5000 }
    $Known = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-Tenants -IncludeErrors).defaultDomainName | Where-Object { $_ }), [StringComparer]::OrdinalIgnoreCase)
    $Counts = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($CacheType in $Type) {
        foreach ($Row in @(Get-CIPPDbItem -TenantFilter 'allTenants' -Type $CacheType -CountsOnly)) {
            $Partition = [string]$Row.PartitionKey
            if ([int]$Row.DataCount -gt 0 -and $Known.Contains($Partition) -and
                (-not $ContinuationToken -or [string]::CompareOrdinal($Partition, $ContinuationToken) -gt 0)) {
                $Counts[$Partition] = [int]$Row.DataCount + $(if ($Counts.ContainsKey($Partition)) { $Counts[$Partition] } else { 0 })
            }
        }
    }
    $Plan = [string[]]@($Counts.Keys)
    [System.Array]::Sort($Plan, [System.Collections.IComparer][StringComparer]::Ordinal)

    $Results = [System.Collections.Generic.List[object]]::new()
    $Rows = 0
    $Index = 0
    while ($Index -lt $Plan.Count -and $Rows -lt $PageSize) {
        $Tenant = $Plan[$Index]
        $Index++
        $Rows += $Counts[$Tenant]
        try {
            foreach ($Item in @(& $Report $Tenant)) {
                if ($Item -is [System.Collections.IDictionary]) {
                    $Item['Tenant'] = $Tenant
                } else {
                    $Item.PSObject.Properties.Remove('Tenant')
                    $Item.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Tenant))
                }
                $Results.Add($Item)
            }
        } catch {
            Write-LogMessage -API 'ReportPage' -tenant $Tenant -message "Failed to get $Type report for tenant: $($_.Exception.Message)" -sev Warning
        }
    }
    if ($Index -lt $Plan.Count) { $Metadata.nextLink = $Plan[$Index - 1] }

    return [PSCustomObject]@{
        Results  = $Results
        Metadata = $Metadata
    }
}
