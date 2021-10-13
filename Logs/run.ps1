using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Log-Request -user $request.headers.'x-ms-client-principal' -message "Accessed Logs" -Sev "Info"
# Interact with query parameters or the body of the request.
$date = if($Request.Query.DateFilter) { $Request.query.DateFilter} else { (get-date).ToString('MMyyyy')}
   $ReturnedLog =  get-content "$($date)" | convertfrom-csv -header "DateTime","Message","User","Sev" -delimiter "|"
if($request.query.last){
    $ReturnedLog = $ReturnedLog | select-object -last $request.query.last
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $ReturnedLog
})
