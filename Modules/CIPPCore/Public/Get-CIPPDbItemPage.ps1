function Get-CIPPDbItemPage {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Reads one page of items of a type from the CIPP Reporting database.
    .DESCRIPTION
    Continuation-token pager over CippReportingDB (PartitionKey = tenant, RowKey = '<Type>-<id>').
    AllTenants walks every managed tenant that has a '<Type>-Count' row; a single tenant walks
    its own partition. Returns raw entities minus the count markers; callers parse Data and
    read the tenant from PartitionKey. A null NextToken means the walk is complete.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [ValidateRange(1, 10000)]
        [int]$PageSize = 5000,
        [string]$ContinuationToken
    )

    # Enforce tenant lock when running inside custom script execution (parity with Get-CIPPDbItem)
    if ($script:CIPPLockedTenant) {
        $TenantFilter = $script:CIPPLockedTenant
    }

    $Table = Get-CippTable -tablename 'CippReportingDB'

    if ($TenantFilter -eq 'AllTenants') {
        $CountRows = Get-CIPPDbItem -TenantFilter 'allTenants' -Type $Type -CountsOnly
        $TenantList = Get-Tenants -IncludeErrors
        $Known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Domain in $TenantList.defaultDomainName) {
            if ($Domain) { $null = $Known.Add([string]$Domain) }
        }
        # Ordinal ascending, to match the walker's range-scan order.
        $Unique = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($Partition in $CountRows.PartitionKey) {
            if ($Partition -and $Known.Contains([string]$Partition)) { $null = $Unique.Add([string]$Partition) }
        }
        $Partitions = [string[]]@($Unique)
        [System.Array]::Sort($Partitions, [System.Collections.IComparer][StringComparer]::Ordinal)
    } else {
        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        if (-not $Tenant) {
            throw "Tenant '$TenantFilter' not found"
        }
        $Partitions = @($Tenant.defaultDomainName)
    }

    $Page = Get-CIPPPagedTableRows -Table $Table -PartitionKeys $Partitions -RowKeyGe "$Type-" -RowKeyLt "$Type." -PageSize $PageSize -ContinuationToken $ContinuationToken
    # Drop the count marker, which sorts inside the range.
    $Items = @($Page.Rows | Where-Object { $_.RowKey -ne "$Type-Count" })

    return [PSCustomObject]@{
        Items     = $Items
        NextToken = $Page.NextToken
    }
}
