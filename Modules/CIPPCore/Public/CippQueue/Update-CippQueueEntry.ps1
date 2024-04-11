function Update-CippQueueEntry {
    Param(
        [Parameter(Mandatory = $true)]
        $RowKey,
        $Status,
        $Name
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
            Update-AzDataTableEntity @CippQueue -Entity $QueueEntry
            $QueueEntry
        } else {
            return $false
        }
    } else {
        return $false
    }
}