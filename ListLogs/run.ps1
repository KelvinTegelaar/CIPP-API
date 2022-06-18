using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Info'

if ($request.Query.Filter -eq 'True') {
    $LogLevel = if ($Request.query.Severity) { ($Request.query.Severity).split(',') } else { 'Info', 'Warn', 'Error', 'Critical', 'Alert' } 
    $PartitionKey = $Request.query.DateFilter
    $username = $Request.Query.User
}
else {
    $LogLevel = 'Info', 'Warn', 'Error', 'Critical', 'Alert'
    $PartitionKey = Get-Date -UFormat '%Y%m%d'
    $username = '*'
}
$Table = Get-CIPPTable

$ReturnedLog = if ($Request.Query.ListLogs) {

    Get-AzTableRow -Table $table | Sort-Object -Unique partitionkey | ForEach-Object {
        @{ 
            value = $_.PartitionKey
            label = $_.PartitionKey
        }
    }
}
else {
    $Rows = Get-AzTableRow -Table $table -PartitionKey $PartitionKey | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username }
    foreach ($Row in $Rows) {
        @{
            DateTime = $Row.TableTimeStamp
            Tenant   = $Row.Tenant
            API      = $Row.API
            Message  = $Row.Message
            User     = $Row.Username
            Severity = $Row.Severity
        }
    }

}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($ReturnedLog)
    })
