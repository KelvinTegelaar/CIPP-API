function Push-AuditLogProcessingBatch {
    <#
    .SYNOPSIS
        Builds the batch of audit log processing tasks from the webhook cache table.
    .DESCRIPTION
        Called as a QueueFunction activity by the AuditLogProcessingOrchestrator.
        Loads CacheWebhooks in pages, groups by tenant, and returns batch items
        for AuditLogTenantProcess activities. Running in an activity isolates
        the memory usage from the timer function.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $WebhookCacheTable = Get-CippTable -TableName 'CacheWebhooks'
    $AllBatchItems = [System.Collections.Generic.List[object]]::new()
    $TotalRows = 0
    $PageSize = 20000
    $Skip = 0

    do {
        $WebhookCache = Get-CIPPAzDataTableEntity @WebhookCacheTable -First $PageSize -Skip $Skip
        $PageCount = $WebhookCache.Count
        $TenantGroups = $WebhookCache | Group-Object -Property PartitionKey
        $WebhookCache = $null

        if ($TenantGroups) {
            $TotalRows += ($TenantGroups | Measure-Object -Property Count -Sum).Sum
            foreach ($TenantGroup in $TenantGroups) {
                $TenantFilter = $TenantGroup.Name
                $RowIds = @($TenantGroup.Group.RowKey)
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
