using namespace System.Net
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$task = $Request.Body | ConvertFrom-Json
$Table = Get-CIPPTable -TableName 'ScheduledTasks'
Add-AzDataTableEntity @Table -Entity @{
    PartitionKey = 'ScheduledTask'
    TaskState = 'Scheduled'
    RowKey = $task.TaskID
    Command = $task.Command
    Parameters = $task.Parameters
    ScheduledTime = $task.ScheduledTime
    Results = 'Not Executed'
    # add more properties here based on what properties your tasks have
}
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = 'Task added successfully.'
})