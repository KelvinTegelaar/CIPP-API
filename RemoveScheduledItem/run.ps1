using namespace System.Net
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$task = @{
    RowKey       = $Request.Query.ID
    PartitionKey = 'ScheduledTask'
}
$Table = Get-CIPPTable -TableName 'ScheduledTasks'
Remove-AzDataTableEntity @Table -Entity $task
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = 'Task removed successfully.' } 
    })