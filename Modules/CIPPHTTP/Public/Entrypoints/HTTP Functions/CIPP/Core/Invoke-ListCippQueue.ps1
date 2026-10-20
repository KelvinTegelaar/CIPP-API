function Invoke-ListCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists active and recent CIPP background processing queue items and their status.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $User = [string]$Request.Headers.'x-ms-client-principal-name'
    $QueueData = Select-CippAllowedQueueData -Queues (Get-CIPPQueueData -Request $Request -TriggerMetadata $TriggerMetadata) -User $User -OwnOnly:(-not $Request.Query.QueueId)

    $Owned = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($User -and $env:CIPPNG -eq 'true') {
        $CippQueue = Get-CippTable -TableName CippQueue
        $SafeUser = ConvertTo-CIPPODataFilterValue -Value $User -Type String
        foreach ($Row in Get-CIPPAzDataTableEntity @CippQueue -Filter "PartitionKey eq 'CippQueue' and Owner eq '$SafeUser'" -Property PartitionKey, RowKey) {
            [void]$Owned.Add($Row.RowKey)
        }
    }

    $Results = foreach ($Queue in $QueueData) {
        # Craft names a queue's run '<Orchestrator>-<QueueId>'
        $QueueId = if ($Queue.RowKey -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { $Matches[0] } else { $Queue.RowKey }
        $Queue | Select-Object *, @{n = 'QueueId'; e = { $QueueId } }, @{n = 'Cancellable'; e = { $Owned.Contains($QueueId) -and $_.Status -in @('Queued', 'Running') } } -ExcludeProperty QueueId, Cancellable
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })
}
