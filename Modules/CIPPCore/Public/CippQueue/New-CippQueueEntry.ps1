function New-CippQueueEntry {
    Param(
        [string]$Name,
        [string]$Link,
        [string]$Reference,
        [int]$TotalTasks
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    $QueueEntry = @{
        PartitionKey = 'CippQueue'
        RowKey       = (New-Guid).Guid.ToString()
        Name         = $Name
        Link         = $Link
        Reference    = $Reference
        Status       = 'Queued'
        TotalTasks   = $TotalTasks
    }
    $CippQueue.Entity = $QueueEntry

    Add-CIPPAzDataTableEntity @CippQueue

    $QueueEntry
}