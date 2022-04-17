using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter

if ($TenantFilter -eq 'AllTenants') {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances"   
    [HttpStatusCode]::OK 
}
else {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances?`$top=999&`$filter=organizationId eq '$TenantFilter'"    
    [HttpStatusCode]::OK
}

if ($GraphRequest.value.count -lt 1) { 
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = "No data found - This client might not be onboarded in Lighthouse" 
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })