function New-CippQueueEntry {
    <#
    .FUNCTIONALITY
        Internal
    #>
    Param(
        [string]$Name,
        [string]$Link,
        [string]$Reference,
        [int]$TotalTasks = 1
    )

    $QueueEntry = @{
        PartitionKey = 'CippQueue'
        RowKey       = (New-Guid).Guid.ToString()
        Name         = $Name
        Link         = $Link
        Reference    = $Reference
        Status       = 'Queued'
        TotalTasks   = $TotalTasks
    }

    if ($env:CIPPNG -eq 'true') {
        [Craft.Services.QueueStatusBridge]::RegisterQueueMetadata($QueueEntry.RowKey, $Name, $Link, $Reference)
        return $QueueEntry
    }

    $CippQueue = Get-CippTable -TableName CippQueue
    $CippQueue.Entity = $QueueEntry
    Add-CIPPAzDataTableEntity @CippQueue

    $QueueEntry
}
