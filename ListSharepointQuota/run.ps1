using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter

if ($Request.Query.TenantFilter -eq 'AllTenants') {
    $UsedStoragePercentage = 'Not Supported'
} else {
    $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter | Where-Object { $_.isInitial -eq $true }).id.Split('.')[0]

    $sharepointToken = (Get-GraphToken -scope "https://$($tenantName)-admin.sharepoint.com/.default" -tenantid $TenantFilter)
    $sharepointToken.Add('accept', 'application/json')
    # Implement a try catch later to deal with sharepoint guest user settings
    $sharepointQuota = (Invoke-RestMethod -Method 'GET' -Headers $sharepointToken -Uri "https://$($tenantName)-admin.sharepoint.com/_api/StorageQuotas()?api-version=1.3.2" -ErrorAction Stop).value | Sort-Object -Property GeoUsedStorageMB -Descending | Select-Object -First 1

    if ($sharepointQuota) {
        $UsedStoragePercentage = [int](($sharepointQuota.GeoUsedStorageMB / $sharepointQuota.TenantStorageMB) * 100)
    }
}

$sharepointQuotaDetails = @{
    GeoUsedStorageMB = $sharepointQuota.GeoUsedStorageMB
    TenantStorageMB  = $sharepointQuota.TenantStorageMB
    Percentage       = $UsedStoragePercentage
    Dashboard        = "$($UsedStoragePercentage) / 100"
}

$StatusCode = [HttpStatusCode]::OK

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $sharepointQuotaDetails
    })