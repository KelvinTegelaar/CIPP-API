function Get-CIPPLicenseSkuName {
    <#
    .SYNOPSIS
        Resolves licence SKU ids to display names
    .DESCRIPTION
        Point lookups against the LicenseSkuNames table. SKUs it does not hold yet are read from the tenant's
        cached licence overview, when a tenant is given, and written back to the table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$SkuIds,

        [string]$TenantFilter
    )

    $Wanted = @($SkuIds | Where-Object { $_ -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if ($Wanted.Count -eq 0) { return @() }

    $Table = Get-CIPPTable -TableName 'LicenseSkuNames'
    $Names = @{}
    # Table queries allow 15 comparisons: the PartitionKey plus 14 RowKeys
    for ($i = 0; $i -lt $Wanted.Count; $i += 14) {
        $Chunk = $Wanted[$i..([Math]::Min($i + 13, $Wanted.Count - 1))]
        $Filter = "PartitionKey eq 'Sku' and ({0})" -f (@($Chunk | ForEach-Object { "RowKey eq '$_'" }) -join ' or ')
        foreach ($Row in Get-CIPPAzDataTableEntity @Table -Filter $Filter) {
            if ($Row.DisplayName) { $Names[$Row.RowKey] = $Row.DisplayName }
        }
    }

    $Missing = @($Wanted | Where-Object { -not $Names.ContainsKey($_) })
    if ($Missing.Count -gt 0 -and $TenantFilter -and $TenantFilter -ne 'AllTenants') {
        $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        if ($Tenant.defaultDomainName) {
            $DbTable = Get-CIPPTable -TableName 'CippReportingDB'
            $Backfill = foreach ($SkuId in $Missing) {
                $RowKey = "LicenseOverview-$SkuId"
                try {
                    # The range also covers the -partN rows of a split entity, so it reassembles
                    $Row = Get-CIPPAzDataTableEntity @DbTable -Filter ("PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}.'" -f $Tenant.defaultDomainName, $RowKey) |
                        Where-Object { $_.RowKey -eq $RowKey } | Select-Object -First 1
                    $Name = if ($Row.Data) { ($Row.Data | ConvertFrom-Json).License }
                } catch {
                    Write-Information "Licence overview lookup failed for $SkuId in $($Tenant.defaultDomainName): $($_.Exception.Message)"
                    $Name = $null
                }
                if ($Name) {
                    $Names[$SkuId] = $Name
                    @{ PartitionKey = 'Sku'; RowKey = [string]$SkuId; DisplayName = [string]$Name }
                }
            }
            if ($Backfill) {
                try {
                    Add-CIPPAzDataTableEntity @Table -Entity @($Backfill) -Force
                } catch {
                    Write-Information "Failed to backfill LicenseSkuNames: $($_.Exception.Message)"
                }
            }
        }
    }

    @(foreach ($SkuId in $Wanted) {
            if ($Names.ContainsKey($SkuId)) { [PSCustomObject]@{ skuId = $SkuId; displayName = $Names[$SkuId] } }
        })
}
