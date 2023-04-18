using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$url = $request.Query.url.tolower()

$GraphRequest = if ($TenantFilter -ne 'AllTenants') {
    $LicRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
    [PSCustomObject]@{
        Tenant   = $TenantFilter
        Licenses = $LicRequest
    }
}
else {
    $Table = Get-CIPPTable -TableName "cache$url"
    $Rows = Get-AzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
    if (!$Rows) {
        $Queue = New-CippQueueEntry -Name $URL -Link '/identity/reports/mfa-report?customerId=AllTenants'
        Push-OutputBinding -Name Msg -Value $url
        [PSCustomObject]@{
            Tenant = 'Loading data for all tenants. Please check back after the job completes'
        }
    }         
    else {
        $Rows.Data | ConvertFrom-Json
    }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }) -clobber