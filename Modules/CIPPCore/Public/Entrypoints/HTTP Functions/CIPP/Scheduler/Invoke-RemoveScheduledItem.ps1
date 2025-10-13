function Invoke-RemoveScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'RemoveScheduledItem'
    $User = $Request.Headers

    $RowKey = $Request.Query.id ? $Request.Query.id : $Request.Body.id
    $task = @{
        RowKey       = $RowKey
        PartitionKey = 'ScheduledTask'
    }
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    Remove-AzDataTableEntity -Force @Table -Entity $task

    $DetailTable = Get-CIPPTable -TableName 'ScheduledTaskDetails'
    $Details = Get-CIPPAzDataTableEntity @DetailTable -Filter "PartitionKey eq '$($RowKey)'" -Property RowKey, PartitionKey, ETag

    if ($Details) {
        Remove-AzDataTableEntity -Force @DetailTable -Entity $Details
    }

    Write-LogMessage -Headers $User -API $APINAME -message "Task removed: $($task.RowKey)" -Sev 'Info'

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = 'Task removed successfully.' }
        })

}
