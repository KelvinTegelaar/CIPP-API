function Get-CIPPAlertSharepointQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $extraHeaders = @{
            'Accept' = 'application/json'
        }
        $sharepointQuota = (New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2")
    } catch {
        return
    }
    if ($sharepointQuota) {
        try {
            if ([int]$InputValue -gt 0) { $Value = [int]$InputValue } else { $Value = 90 }
        } catch {
            $Value = 90
        }
        $GeoUsedStorageMB = ($sharepointQuota.GeoUsedStorageMB | Measure-Object -Sum).Sum
        $TenantStorageMB = $sharepointQuota.TenantStorageMB | Select-Object -First 1
        $UsedStoragePercentage = [int](($GeoUsedStorageMB / $TenantStorageMB) * 100)
        if ($UsedStoragePercentage -gt $Value) {
            $AlertData = [PSCustomObject]@{
                UsedStoragePercentage = $UsedStoragePercentage
                StorageUsed           = ([math]::Round($GeoUsedStorageMB / 1024, 2))
                StorageQuota          = ([math]::Round($TenantStorageMB / 1024, 2))
                AlertQuotaThreshold   = $Value
                Tenant                = $TenantFilter
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    }
}
