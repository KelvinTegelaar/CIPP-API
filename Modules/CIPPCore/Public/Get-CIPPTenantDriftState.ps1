function Get-CIPPTenantDriftState {
    <#
    .SYNOPSIS
        Reads a tenant's drift decisions from the tenantDrift table.
    .DESCRIPTION
        Decisions are stored under the tenant's customerId. Rows saved before that are keyed by the
        domain that was the default at the time, so the default and initial domain partitions are
        read too. Per standard a decided status beats New, then the customerId row, then the newest.
    .PARAMETER TenantFilter
        The tenant's customerId, default domain or initial domain.
    .PARAMETER Lookup
        A Get-CIPPTenantLookup result, so a caller reading many tenants builds it once.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        $Lookup
    )

    $Tenant = $(try { ($Lookup ?? (Get-CIPPTenantLookup))[$TenantFilter] } catch { $null })
    $PartitionKey = if ($Tenant.customerId) { "$($Tenant.customerId)" } else { $TenantFilter }
    $Keys = @(@($PartitionKey, $Tenant.defaultDomainName, $Tenant.initialDomainName, $TenantFilter) | Where-Object { $_ } | Select-Object -Unique)

    $Table = Get-CippTable -tablename 'tenantDrift'
    $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter (@($Keys | ForEach-Object { "PartitionKey eq '$_'" }) -join ' or '))

    $Rank = { param($Row) ($(if ("$($Row.Status)" -and "$($Row.Status)" -ne 'New') { 2 } else { 0 }) + $(if ("$($Row.PartitionKey)" -eq $PartitionKey) { 1 } else { 0 })) }
    $States = @{}
    foreach ($Row in $Rows) {
        $Name = [string]$Row.StandardName
        if ([string]::IsNullOrWhiteSpace($Name)) { continue }
        $Held = $States[$Name]
        if (-not $Held) { $States[$Name] = $Row; continue }
        $RowRank = & $Rank $Row
        $HeldRank = & $Rank $Held
        if ($RowRank -gt $HeldRank -or ($RowRank -eq $HeldRank -and $Row.Timestamp -gt $Held.Timestamp)) { $States[$Name] = $Row }
    }

    [PSCustomObject]@{
        PartitionKey = $PartitionKey
        Rows         = $Rows
        States       = $States
    }
}
