using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
if ($TenantFilter -eq "AllTenants") { $TenantFilter = (get-tenants).customerId }
try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/inactiveUsers?`$count=true" -tenantid $env:TenantId | Where-Object { $_.tenantId -in $TenantFilter }
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
