using namespace System.Net

function Invoke-ListSharepointQuota {
    <#
    .SYNOPSIS
    List SharePoint storage quota and usage information
    
    .DESCRIPTION
    Retrieves SharePoint storage quota and usage information for a tenant including used storage, total storage, and percentage usage
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
        
    .NOTES
    Group: Teams & SharePoint
    Summary: List Sharepoint Quota
    Description: Retrieves SharePoint storage quota and usage information for a tenant including used storage, total storage, and percentage usage through SharePoint Admin API
    Tags: SharePoint,Storage,Quota,Usage
    Parameter: tenantFilter (string) [query] - Target tenant identifier (use 'AllTenants' for all tenants)
    Response: Returns an object with the following properties:
    Response: - GeoUsedStorageMB (number): Used storage in megabytes
    Response: - TenantStorageMB (number): Total tenant storage in megabytes
    Response: - Percentage (string/number): Used storage percentage or status message
    Response: - Dashboard (string): Formatted dashboard display string
    Response: For AllTenants: Returns "Not Supported" for percentage
    Response: On error: Returns "Not available" for percentage
    Example: {
      "GeoUsedStorageMB": 10240,
      "TenantStorageMB": 102400,
      "Percentage": 10,
      "Dashboard": "10 / 100"
    }
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
    }
    else {
        try {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $extraHeaders = @{
                'Accept' = 'application/json'
            }
            $SharePointQuota = (New-GraphGetRequest -extraHeaders $extraHeaders -scope "$($SharePointInfo.AdminUrl)/.default" -tenantid $TenantFilter -uri "$($SharePointInfo.AdminUrl)/_api/StorageQuotas()?api-version=1.3.2") | Sort-Object -Property GeoUsedStorageMB -Descending | Select-Object -First 1

            if ($SharePointQuota) {
                $UsedStoragePercentage = [int](($SharePointQuota.GeoUsedStorageMB / $SharePointQuota.TenantStorageMB) * 100)
            }
        }
        catch {
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
