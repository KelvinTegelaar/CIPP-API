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
$TableURLName = ($request.query.url.tolower() -split '?' | Select-Object -First 1).toString()

$Queue = New-CippQueueEntry -Name $URL -Link '/identity/reports/mfa-report?customerId=AllTenants'
Push-OutputBinding -Name Msg -Value $url


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    }) -clobber