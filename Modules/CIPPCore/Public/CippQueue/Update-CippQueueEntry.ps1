function Update-CippQueueEntry {
    <#
    .FUNCTIONALITY
        Internal
    #>
    param(
        [Parameter(Mandatory = $true)]
        $RowKey,
        $Status,
        $Name,
        $TotalTasks,
        [switch]$IncrementTotalTasks
    )

    $CippQueue = Get-CippTable -TableName CippQueue

    if ($RowKey) {
        $QueueEntry = Get-CIPPAzDataTableEntity @CippQueue -Filter ("RowKey eq '{0}'" -f $RowKey)

        if ($QueueEntry) {
            if ($Status) {
                $QueueEntry.Status = $Status
            }
            if ($Name) {
                $QueueEntry.Name = $Name
            }
            if ($TotalTasks) {
                if ($IncrementTotalTasks) {
                    # Increment the existing total
                    $QueueEntry.TotalTasks = [int]$QueueEntry.TotalTasks + [int]$TotalTasks
                } else {
                    # Set the total directly
                    $QueueEntry.TotalTasks = $TotalTasks
                }
            }
            Add-CIPPAzDataTableEntity @CippQueue -Entity $QueueEntry -Force
            $QueueEntry
        } else {
            return $false
        }
    } else {
        return $false
    }
}
