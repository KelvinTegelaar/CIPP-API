using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

try {
    $Results = Remove-CIPPGraphSubscription -TenantFilter $Request.query.TenantFilter -CIPPID $Request.query.CIPPID
    $body = [pscustomobject]@{"Results" = $Results }
}
catch {
    Write-LogMessage -user $request.headers.'x-ms-client-principal'  -API $APINAME  -message "Failed to remove webhook alert. $($_.Exception.Message)" -Sev "Error"
    $body = [pscustomobject]@{"Results" = "Failed to remove webhook alert: $($_.Exception.Message)" }
}


# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

