using namespace System.Net
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$task = $Request.Body | ConvertFrom-Json
$Table = Get-CIPPTable -TableName 'ScheduledTasks'
Remove-AzDataTableEntity @Table -PartitionKey 'ScheduledTask' -RowKey $task.TaskID -force
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = 'Task removed successfully.'
})