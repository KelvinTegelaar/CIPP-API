function Set-CIPPDBCacheSharePointUsageReport {
    <#
    .SYNOPSIS
        Caches SharePoint tenant-wide quota usage report for a tenant

    .DESCRIPTION
        Retrieves SharePoint Online storage quota live from the SPO admin endpoint
        this can be delayed for multiple days due to SPO server processing times

    .PARAMETER TenantFilter
        The tenant to cache SharePoint quota usage report for
    
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
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'SharePointUsageReport' -TenantFilter $TenantFilter -Preset SharePoint -SkipLog

        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have SharePoint license, skipping SharePoint quota usage report cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointUsageReport' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint tenant-wide quota usage report' -sev Debug

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $extraHeaders = @{
            'Accept' = 'application/json'
        }
        $SharePointQuota = New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2" -asapp $true -UseCertificate

        # Handle empty response gracefully
        if ($null -eq $SharePointQuota) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'SharePoint quota report returned null or empty' -sev Warning
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointUsageReport' -Data @() -AddCount -ClearOnEmpty
            return
        }

        $GeoUsedStorageMB = (@($SharePointQuota) | ForEach-Object { [double]($_.GeoUsedStorageMB ?? 0) } | Measure-Object -Sum).Sum
        $TenantStorageRaw = @($SharePointQuota.TenantStorageMB | Where-Object { $_ }) | Select-Object -First 1
        $TenantStorageMB = if ($null -ne $TenantStorageRaw) { [double]$TenantStorageRaw } else { 0 }
        $GeoLocations = @(foreach ($Geo in @($SharePointQuota)) {
            if ($null -eq $Geo) { continue }
            [PSCustomObject]@{
                GeoLocation           = $Geo.GeoLocation
                GeoUsedStorageMB      = [double]($Geo.GeoUsedStorageMB ?? 0)
                GeoAllocatedStorageMB = [double]($Geo.GeoAllocatedStorageMB ?? 0)
                GeoAvailableStorageMB = [double]($Geo.GeoAvailableStorageMB ?? 0)
            }
        })

        if ($TenantStorageMB) {
            $UsedStoragePercentage = [int](($GeoUsedStorageMB / $TenantStorageMB) * 100)
        }

        $SharePointQuotaDetails = @{
            GeoUsedStorageMB = $GeoUsedStorageMB
            TenantStorageMB  = $TenantStorageMB
            Percentage       = $UsedStoragePercentage
            Dashboard        = "$($UsedStoragePercentage) / 100"
            GeoLocations     = @($GeoLocations)
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointUsageReport' -Data $SharePointQuotaDetails -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached SharePoint quota usage report" -sev Debug

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint quota usage report: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
