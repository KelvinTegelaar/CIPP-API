using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Info"


$LogLevel = if ($Request.Query.Severity) { ($Request.query.Severity).split(',') } else { "Info", "Warn", "Error", "Critical" }
$date = if ($Request.Query.DateFilter) { $Request.query.DateFilter } else { (Get-Date).ToString('ddMMyyyy') }
$username = if ($Request.Query.User) { $Request.Query.User } else { '*' }
$ReturnedLog = if ($Request.Query.ListLogs) {
    Get-ChildItem "Logs" | Select-Object Name
}
else {
    Get-Content "Logs\$($date).log" | ConvertFrom-Csv -Header "DateTime", "Tenant", "API", "Message", "User", "Severity" -Delimiter "|" | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username }
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $ReturnedLog
    })
