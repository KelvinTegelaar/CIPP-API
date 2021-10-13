using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$top=999" -tenantid $TenantFilter | where-object -property "@odata.type" -eq '#microsoft.graph.win32LobApp'


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })