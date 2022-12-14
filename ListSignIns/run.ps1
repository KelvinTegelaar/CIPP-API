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
    if ($Request.query.failedlogonOnly) {
        $FailedLogons = " and (status/errorCode eq 50126)"
    }
    
    $filters = if ($Request.query.Filter) { 
        $request.query.filter
    }
    else {
        $currentTime = Get-Date -Format 'yyyy-MM-dd'
        $ts = (Get-Date).AddDays(-7)
        $endTime = $ts.ToString('yyyy-MM-dd')
        "createdDateTime ge $($endTime) and createdDateTime lt $($currentTime) and userDisplayName ne 'On-Premises Directory Synchronization Service Account' $FailedLogons"
    }
    Write-Host $Filters

    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&`$filter=$($filters)" -tenantid $TenantFilter -erroraction stop
    $response = $GraphRequest  | Select-Object *, 
    @{l = "additionalDetails"; e = { $_.status.additionalDetails } } ,
    @{l = "errorCode"; e = { $_.status.errorCode } },
    @{l = "locationcipp"; e = { "$($_.location.city) - $($_.location.countryOrRegion)" } } 
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
