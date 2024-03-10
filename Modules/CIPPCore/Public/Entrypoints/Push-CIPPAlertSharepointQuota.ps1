
function Push-CIPPAlertSharepointQuota {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Item
    )
    Try {
        $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $Item.Tenant | Where-Object { $_.isInitial -eq $true }).id.Split('.')[0]
        $sharepointToken = (Get-GraphToken -scope "https://$($tenantName)-admin.sharepoint.com/.default" -tenantid $Item.Tenant)
        $sharepointToken.Add('accept', 'application/json')
        $sharepointQuota = (Invoke-RestMethod -Method 'GET' -Headers $sharepointToken -Uri "https://$($tenantName)-admin.sharepoint.com/_api/StorageQuotas()?api-version=1.3.2" -ErrorAction Stop).value
        if ($sharepointQuota) {
            if ($Item.value) { $Value = $Item.value } else { $Value = 90 }
            $UsedStoragePercentage = [int](($sharepointQuota.GeoUsedStorageMB / $sharepointQuota.TenantStorageMB) * 100)
            if ($UsedStoragePercentage -gt $Value) {
                Write-AlertMessage -tenant $($Item.tenant) -message "SharePoint Storage is at $($UsedStoragePercentage)%. Your alert threshold is $($Value)%"
            }
        }
    } catch {
    }


}