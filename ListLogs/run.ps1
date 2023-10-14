using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

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

    Get-AzDataTableEntity @Table -Property PartitionKey | Sort-Object -Unique PartitionKey | Select-Object PartitionKey | ForEach-Object {
        @{ 
            value = $_.PartitionKey
            label = $_.PartitionKey
        }
    }
}
else {
    $Filter = "PartitionKey eq '{0}'" -f $PartitionKey
    $Rows = Get-AzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Severity -In $LogLevel -and $_.user -like $username }
    foreach ($Row in $Rows) {
        @{
            DateTime = $Row.Timestamp
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
