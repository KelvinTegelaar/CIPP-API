using namespace System.Net

Function Invoke-ListSharepointQuota {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    if ($TenantFilter -eq 'AllTenants') {
        $UsedStoragePercentage = 'Not Supported'
    } else {
        try {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $extraHeaders = @{
                'Accept' = 'application/json'
            }
            $SharePointQuota = (New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2") | Sort-Object -Property GeoUsedStorageMB -Descending | Select-Object -First 1

            if ($SharePointQuota) {
                $UsedStoragePercentage = [int](($SharePointQuota.GeoUsedStorageMB / $SharePointQuota.TenantStorageMB) * 100)
            }
        } catch {
            $UsedStoragePercentage = 'Not available'
        }
    }

    $SharePointQuotaDetails = @{
        GeoUsedStorageMB = $SharePointQuota.GeoUsedStorageMB
        TenantStorageMB  = $SharePointQuota.TenantStorageMB
        Percentage       = $UsedStoragePercentage
        Dashboard        = "$($UsedStoragePercentage) / 100"
    }

    $StatusCode = [HttpStatusCode]::OK

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $SharePointQuotaDetails
        })

}
