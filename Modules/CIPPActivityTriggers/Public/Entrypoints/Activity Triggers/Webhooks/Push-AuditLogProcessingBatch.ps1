function Push-AuditLogProcessingBatch {
    <#
    .SYNOPSIS
        Builds the batch of audit log processing tasks from the webhook cache table.
    .DESCRIPTION
        Called as a QueueFunction activity by the AuditLogProcessingOrchestrator.
        Loads CacheWebhooks in pages, groups by tenant, and returns batch items
        for AuditLogTenantProcess activities. Running in an activity isolates
        the memory usage from the timer function.

        Rows are stamped with CippProcessing = true and CippProcessingStarted timestamp
        before being included in the batch, so that subsequent 15-minute timer runs skip
        them instead of spawning duplicate activities. Rows stuck in processing state for
        more than 4 hours (e.g. from a worker crash) are automatically recovered and
        re-queued on the next run.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $WebhookCacheTable = Get-CippTable -TableName 'CacheWebhooks'
    $AllBatchItems = [System.Collections.Generic.List[object]]::new()
    $TotalRows = 0
    $PageSize = 20000
    $Skip = 0
    $NowUtc = (Get-Date).ToUniversalTime()
    $StaleThreshold = $NowUtc.AddHours(-4)

    do {
        # Fetch only the properties needed to determine claim status and build the batch
        $WebhookCache = Get-CIPPAzDataTableEntity @WebhookCacheTable -First $PageSize -Skip $Skip -Property @('PartitionKey', 'RowKey', 'ETag', 'Timestamp', 'CippProcessing')
        $PageCount = $WebhookCache.Count

        # Filter client-side: skip rows actively claimed unless the claim is stale (> 4 hours old)
        $TenantGroups = $WebhookCache | Where-Object {
            -not $_.CippProcessing -or
            ($_.Timestamp -and $_.Timestamp.UtcDateTime -lt $StaleThreshold)
        } | Group-Object -Property PartitionKey
        $WebhookCache = $null

        if ($TenantGroups) {
            foreach ($TenantGroup in $TenantGroups) {
                $TenantFilter = $TenantGroup.Name
                $Rows = @($TenantGroup.Group)
                $RowIds = @($Rows.RowKey)

                # Claim these rows so subsequent timer runs skip them (UpsertMerge preserves JSON and other fields)
                # The entity Timestamp is updated automatically on write and used for stale detection.
                foreach ($Row in $Rows) {
                    $ClaimEntity = [PSCustomObject]@{
                        PartitionKey   = $Row.PartitionKey
                        RowKey         = $Row.RowKey
                        CippProcessing = $true
                    }
                    Add-CIPPAzDataTableEntity @WebhookCacheTable -Entity $ClaimEntity -OperationType UpsertMerge
                }

                $TotalRows += $RowIds.Count
                for ($i = 0; $i -lt $RowIds.Count; $i += 500) {
                    $BatchRowIds = $RowIds[$i..([Math]::Min($i + 499, $RowIds.Count - 1))]
                    $AllBatchItems.Add([PSCustomObject]@{
                            TenantFilter = $TenantFilter
                            RowIds       = $BatchRowIds
                            FunctionName = 'AuditLogTenantProcess'
                        })
                }
            }
            $TenantGroups = $null
        }

        if ($PageCount -lt $PageSize) { break }
        $Skip += $PageSize
    } while ($PageCount -eq $PageSize)

    if ($AllBatchItems.Count -gt 0) {
        $ProcessQueue = New-CippQueueEntry -Name 'Audit Logs Process' -Reference 'AuditLogsProcess' -TotalTasks $TotalRows
        foreach ($BatchItem in $AllBatchItems) {
            $BatchItem | Add-Member -MemberType NoteProperty -Name QueueId -Value $ProcessQueue.RowKey -Force
        }
        Write-Information "AuditLogProcessingBatch: $($AllBatchItems.Count) batch items across $TotalRows rows"
    } else {
        Write-Information 'AuditLogProcessingBatch: no webhook cache entries found'
    }

    return $AllBatchItems.ToArray()
}
