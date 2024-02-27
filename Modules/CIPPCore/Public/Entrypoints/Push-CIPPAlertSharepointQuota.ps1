
function Push-CIPPAlertSharepointQuota {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    Try {
        $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $QueueItem.Tenant | Where-Object { $_.isInitial -eq $true }).id.Split('.')[0]
        $sharepointToken = (Get-GraphToken -scope "https://$($tenantName)-admin.sharepoint.com/.default" -tenantid $QueueItem.Tenant)
        $sharepointToken.Add('accept', 'application/json')
        $sharepointQuota = (Invoke-RestMethod -Method 'GET' -Headers $sharepointToken -Uri "https://$($tenantName)-admin.sharepoint.com/_api/StorageQuotas()?api-version=1.3.2" -ErrorAction Stop).value
        if ($sharepointQuota) {
            $UsedStoragePercentage = [int](($sharepointQuota.GeoUsedStorageMB / $sharepointQuota.TenantStorageMB) * 100)
            if ($UsedStoragePercentage -gt 90) {
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "SharePoint Storage is at $($UsedStoragePercentage)%"
            }
        }
    } catch {
    }
}
