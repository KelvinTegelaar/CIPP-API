using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
# Interact with query parameters or the body of the request.
$TenantFilter = $Request.Query.TenantFilter
try {
    $currentTime = Get-Date -Format 'yyyy-MM-ddTHH:MM:ss'
    $ts = (Get-Date).AddDays(-30)
    $endTime = $ts.ToString('yyyy-MM-ddTHH:MM:ss')
    ##Create Filter for basic auth sign-ins
    $filters = "createdDateTime ge $($endTime)Z and createdDateTime lt $($currentTime)Z and userDisplayName ne 'On-Premises Directory Synchronization Service Account'"

    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=$($filters)" -tenantid $TenantFilter -erroraction stop
    $response = $GraphRequest
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Retrieved sign in report' -Sev 'Debug' -tenant $TenantFilter
    
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($response)
        })
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to retrieve Sign In report: $($_.Exception.message) " -Sev 'Error' -tenant $TenantFilter
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = '500'
            Body       = $(Get-NormalizedError -message $_.Exception.message)
        })
}
