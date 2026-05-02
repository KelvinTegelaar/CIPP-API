function Set-CippQueueTask {
    <#
    .FUNCTIONALITY
        Internal
    #>
    param(
        [string]$QueueId,
        [string]$TaskId = (New-Guid).Guid.ToString(),
        [string]$Name,
        [ValidateSet('Queued', 'Running', 'Completed', 'Failed')]
        [string]$Status = 'Queued',
        [string]$Message
    )

    if ($env:CIPPNG -eq 'true') {
        return @{ RowKey = $TaskId; QueueId = $QueueId; Name = $Name; Status = $Status }
    }

    $CippQueueTasks = Get-CippTable -TableName CippQueueTasks

    $QueueTaskEntry = @{
        PartitionKey = 'Task'
        RowKey       = $TaskId
        QueueId      = $QueueId
        Name         = $Name
        Status       = $Status
    }
    if ($Message) {
        $QueueTaskEntry.Message = $Message
    }
    $CippQueueTasks.Entity = $QueueTaskEntry

    Add-CIPPAzDataTableEntity @CippQueueTasks -Force
    return $QueueTaskEntry
}
