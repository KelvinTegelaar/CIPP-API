using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host "$($Request.query.ID)"
# Interact with query parameters or the body of the request.

try {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Reset password for $($REquest.query.id)" -Sev "Info"
}
catch {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Failed to reset password for $($Request.query.id): $($_.Exception.Message)" -Sev "Error"

}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })