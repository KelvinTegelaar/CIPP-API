function Set-CIPPDBCacheLicenseOverview {
    <#
    .SYNOPSIS
        Caches license overview for a tenant

    .PARAMETER TenantFilter
        The tenant to cache license overview for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching license overview' -sev Debug

        $LicenseOverview = Get-CIPPLicenseOverview -TenantFilter $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseOverview' -Data @($LicenseOverview) -AddCount

        $SkuNames = @{}
        foreach ($Sku in $LicenseOverview) {
            if ($Sku.skuId -and $Sku.License) { $SkuNames[([string]$Sku.skuId).ToLowerInvariant()] = [string]$Sku.License }
        }
        if ($SkuNames.Count -gt 0) {
            $Known = @(Get-CIPPLicenseSkuName -SkuIds @($SkuNames.Keys)).skuId
            $NewNames = @(foreach ($SkuId in $SkuNames.Keys) {
                    if ($SkuId -notin $Known) { @{ PartitionKey = 'Sku'; RowKey = $SkuId; DisplayName = $SkuNames[$SkuId] } }
                })
            if ($NewNames.Count -gt 0) {
                $NameTable = Get-CIPPTable -TableName 'LicenseSkuNames'
                try {
                    Add-CIPPAzDataTableEntity @NameTable -Entity $NewNames
                } catch {
                    Write-Verbose "LicenseSkuNames insert skipped: $($_.Exception.Message)"
                }
            }
        }
        $LicenseOverview = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached license overview successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache license overview: $($_.Exception.Message)" -sev Error
    }
}
