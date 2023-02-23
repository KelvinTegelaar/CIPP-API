using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Write-Host "$($Request.query.ID)"
# Interact with query parameters or the body of the request.

$applicationid = if ($request.query.applicationid) { $request.query.applicationid } else { $env:ApplicationID } 
$Results = get-tenants | ForEach-Object {
    [PSCustomObject]@{
        defaultDomainName = $_.defaultDomainName
        link              = "https://login.microsoftonline.com/$($_.customerId)/v2.0/adminconsent?client_id=$applicationid"
    }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
    })
