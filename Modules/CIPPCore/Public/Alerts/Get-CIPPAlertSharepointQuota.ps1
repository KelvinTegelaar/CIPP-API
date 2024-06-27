
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
            $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
        $sharepointToken = (Get-GraphToken -scope "https://$($tenantName)-admin.sharepoint.com/.default" -tenantid $TenantFilter)
        $sharepointToken.Add('accept', 'application/json')
        $sharepointQuota = (Invoke-RestMethod -Method 'GET' -Headers $sharepointToken -Uri "https://$($tenantName)-admin.sharepoint.com/_api/StorageQuotas()?api-version=1.3.2" -ErrorAction Stop).value
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
            $AlertData = "SharePoint Storage is at $($UsedStoragePercentage)%. Your alert threshold is $($Value)%"
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    }
}