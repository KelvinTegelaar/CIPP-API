using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Interact with query parameters or the body of the request.
$tenantfilter = $Request.Query.TenantFilter
$AlertFilter = $Request.Query.GUID
$Status = $Request.Query.Status
$AssignBody = '{"status":"' + $Status + '","vendorInformation":{"provider":"' + $Request.query.provider + '","vendor":"' + $Request.query.vendor + '"}}'
try {       
    $GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/security/alerts/$AlertFilter" -type PATCH -tenantid $TenantFilter -body $Assignbody
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Set alert $AlertFilter to status $Status" -Sev "Info"
    $body = [pscustomobject]@{"Results" = "Set status for alert to $Status" }

}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to update alert $($AlertFilter): $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to change status: $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
