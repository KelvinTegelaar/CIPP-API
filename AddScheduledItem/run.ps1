using namespace System.Net
param($Request, $TriggerMetadata)
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$task = $Request.Body
$Table = Get-CIPPTable -TableName 'ScheduledTasks'

$propertiesToCheck = @('Webhook', 'Email', 'PSA')
$PostExecution = ($propertiesToCheck | Where-Object { $task.PostExecution.$_ -eq $true }) -join ','
$Parameters = ($task.Parameters | ConvertTo-Json -Compress)
if ($Parameters -eq 'null') { $Parameters = '' }
$entity = @{
    PartitionKey  = [string]'ScheduledTask'
    TaskState     = [string]'Planned'
    RowKey        = [string]"$(New-Guid)"
    Tenant        = [string]$task.TenantFilter
    Name          = [string]$task.Name
    Command       = [string]$task.Command.value
    Parameters    = [string]$Parameters
    ScheduledTime = [string]$task.ScheduledTime
    Recurrence    = [string]$task.Recurrence.value
    PostExecution = [string]$PostExecution
    Results       = 'Planned'
}
Write-Host "entity: $($entity | ConvertTo-Json)"
Add-AzDataTableEntity @Table -Entity $entity
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = 'Task added successfully.' }
    })