using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Info"

if ($request.Query.filter -eq "True") {
    $LogLevel = ($Request.query.Severity).split(',') 
    $date = $Request.query.DateFilter
    $username = $Request.Query.User
}
else {
    $LogLevel = "Info", "Warn", "Error", "Critical"
    $date = (Get-Date).ToString('ddMMyyyy')
    $username = '*'
}

$ReturnedLog = if ($Request.Query.ListLogs) {
    Get-ChildItem "Logs" | Select-Object Name, BaseName | ForEach-Object { @{
            value = $_.BaseName
            label = $_.BaseName
        } }
}
else {
    Get-Content "Logs\$($date).log" | ConvertFrom-Csv -Header "DateTime", "Tenant", "API", "Message", "User", "Severity" -Delimiter "|" | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username }
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($ReturnedLog)
    })
