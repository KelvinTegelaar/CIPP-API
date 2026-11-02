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
    # Only the user who started a queue may cancel it (ExecCancelCippQueue).
    if ($script:CippRealtimeUser) { $QueueEntry.Owner = [string]$script:CippRealtimeUser }

    if ($env:CIPPNG -eq 'true') {
        [Craft.Services.QueueStatusBridge]::RegisterQueueMetadata($QueueEntry.RowKey, $Name, $Link, $Reference)
        Add-CIPPRealtimeWatch -JobId $QueueEntry.RowKey -Run
        if ($QueueEntry.Owner) {
            $CippQueue = Get-CippTable -TableName CippQueue
            $CippQueue.Entity = $QueueEntry
            Add-CIPPAzDataTableEntity @CippQueue
        }
        return $QueueEntry
    }

    $CippQueue = Get-CippTable -TableName CippQueue
    $CippQueue.Entity = $QueueEntry
    Add-CIPPAzDataTableEntity @CippQueue

    $QueueEntry
}
