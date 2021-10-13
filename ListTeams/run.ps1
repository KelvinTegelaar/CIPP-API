using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
if($request.query.type -eq "List"){
$GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayname,description,visibility,mailNickname" -tenantid $TenantFilter
}
$TeamID = $request.query.ID
if($request.query.type -eq "Team"){ $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/teams/$($TeamID)" -tenantid $TenantFilter
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })