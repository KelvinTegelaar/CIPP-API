using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
# Interact with query parameters or the body of the request.
$date = if ($Request.Query.DateFilter) { $Request.query.DateFilter } else { (Get-Date).ToString('MMyyyy') }
$ReturnedLog = Get-Content "$($date)" | ConvertFrom-Csv -Header "DateTime", "Message", "User", "Sev" -Delimiter "|"
if ($request.query.last) {
    $ReturnedLog = $ReturnedLog | Select-Object -Last $request.query.last
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $ReturnedLog
    })
