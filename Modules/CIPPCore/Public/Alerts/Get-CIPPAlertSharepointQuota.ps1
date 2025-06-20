function Get-CIPPAlertSharepointQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    Try {
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
        $UsedStoragePercentage = [int](($sharepointQuota.GeoUsedStorageMB / $sharepointQuota.TenantStorageMB) * 100)
        if ($UsedStoragePercentage -gt $Value) {
            $AlertData = "SharePoint Storage is at $($UsedStoragePercentage)% [$([math]::Round($sharepointQuota.GeoUsedStorageMB / 1024, 2)) GB/$([math]::Round($sharepointQuota.TenantStorageMB / 1024, 2)) GB]. Your alert threshold is $($Value)%"
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    }
}
