using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {
    $GraphRequest = New-GraphPOSTRequest -type "POST" -NoAuthCheck $True -uri "https://traf-pcsvcadmin-prod.trafficmanager.net/CustomerServiceAdminApi/Web/v1/granularAdminRelationships/7aad2ff9-4326-4e1e-ad2d-90ca66eac1c8-529ceae5-f210-42e8-9645-7f44fb00e543/UpdateStatus" -tenantid $ENV:TenantId  -scope 'https://api.partnercustomeradministration.microsoft.com/.default' -body '{"status":"terminationRequested"}'

    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
