using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
$userid = $Request.Query.UserID

if($request.query.type -eq "ApProfile"){
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles?`$expand=assignments" -tenantid $TenantFilter
}

if($request.query.type -eq "ESP"){
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations?`$expand=assignments" -tenantid $TenantFilter | where-object -property "@odata.type" -eq "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = (convertto-json @($GraphRequest))
    })