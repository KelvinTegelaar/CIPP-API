function Get-CIPPLicenseSkuName {
    <#
    .SYNOPSIS
        Resolves licence SKU ids to display names
    .DESCRIPTION
        Names come from the shipped ConversionTable.csv first, then the LicenseSkuNames table for SKUs the CSV does
        not list. SKUs neither holds are read from the tenant's cached licence overview, when a tenant is given, and
        written back to the table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$SkuIds,

        [string]$TenantFilter
    )

    $CsvNames = (Get-CIPPConversionTable).NameBySkuId
    $Names = @{}
    $Wanted = [System.Collections.Generic.List[string]]::new()
    $Missing = [System.Collections.Generic.List[string]]::new()
    foreach ($SkuId in $SkuIds) {
        if ($SkuId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { continue }
        $SkuId = $SkuId.ToLowerInvariant()
        if ($Names.ContainsKey($SkuId) -or $Missing.Contains($SkuId)) { continue }
        $Wanted.Add($SkuId)
        if ($CsvNames.ContainsKey($SkuId)) { $Names[$SkuId] = $CsvNames[$SkuId] } else { $Missing.Add($SkuId) }
    }

    if ($Missing.Count -gt 0) {
        $Table = Get-CIPPTable -TableName 'LicenseSkuNames'
        # Point query per SKU: OR-ed RowKey conditions make the table scan the whole partition
        foreach ($SkuId in $Missing) {
            foreach ($Row in Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Sku' and RowKey eq '$SkuId'") {
                if ($Row.DisplayName) { $Names[$Row.RowKey] = $Row.DisplayName }
            }
        }
        $Missing = @($Missing.Where({ -not $Names.ContainsKey($_) }))
    }

    if ($Missing.Count -gt 0 -and $TenantFilter -and $TenantFilter -ne 'AllTenants') {
        $Tenant = @(Get-Tenants -TenantFilter $TenantFilter)[0]
        if ($Tenant.defaultDomainName) {
            $DbTable = Get-CIPPTable -TableName 'CippReportingDB'
            $Backfill = foreach ($SkuId in $Missing) {
                $RowKey = "LicenseOverview-$SkuId"
                try {
                    # The range also covers the -partN rows of a split entity, so it reassembles
                    $Row = @((Get-CIPPAzDataTableEntity @DbTable -Filter ("PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{1}.'" -f $Tenant.defaultDomainName, $RowKey)).Where({ $_.RowKey -eq $RowKey }, 'First'))[0]
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
