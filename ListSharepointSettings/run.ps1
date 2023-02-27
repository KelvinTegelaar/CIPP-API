using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$tenant = $Request.Query.TenantFilter
$User = $Request.query.user
$USERToGet = $Request.query.usertoGet
$body = '{"isResharingByExternalUsersEnabled": "False"}'
$Request = New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -Type patch -Body $body -ContentType "application/json"
    
Write-LogMessage  -API "Standards" -tenant $tenantFilter -message "Disabled Password Expiration" -sev Info
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
