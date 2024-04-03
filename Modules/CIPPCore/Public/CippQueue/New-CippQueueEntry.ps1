function New-CippQueueEntry {
    Param(
        $Name,
        $Link,
        $Reference
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    $QueueEntry = @{
        PartitionKey = 'CippQueue'
        RowKey       = (New-Guid).Guid.ToString()
        Name         = $Name
        Link         = $Link
        Reference    = $Reference
        Status       = 'Queued'
    }
    $CippQueue.Entity = $QueueEntry

    Add-CIPPAzDataTableEntity @CippQueue

    $QueueEntry
}