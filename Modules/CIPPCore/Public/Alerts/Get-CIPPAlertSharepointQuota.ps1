
function Get-CIPPAlertSharepointQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )
    Try {
        $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter | Where-Object { $_.isInitial -eq $true }).id.Split('.')[0]
        $sharepointToken = (Get-GraphToken -scope "https://$($tenantName)-admin.sharepoint.com/.default" -tenantid $TenantFilter)
        $sharepointToken.Add('accept', 'application/json')
        $sharepointQuota = (Invoke-RestMethod -Method 'GET' -Headers $sharepointToken -Uri "https://$($tenantName)-admin.sharepoint.com/_api/StorageQuotas()?api-version=1.3.2" -ErrorAction Stop).value
        if ($sharepointQuota) {
            if ($input -Is [Boolean]) { $Value = 90 } else { $Value = $input }
            $UsedStoragePercentage = [int](($sharepointQuota.GeoUsedStorageMB / $sharepointQuota.TenantStorageMB) * 100)
            if ($UsedStoragePercentage -gt $Value) {
                $AlertData = "SharePoint Storage is at $($UsedStoragePercentage)%. Your alert threshold is $($Value)%"
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
            }
        }
    } catch {
    }


}