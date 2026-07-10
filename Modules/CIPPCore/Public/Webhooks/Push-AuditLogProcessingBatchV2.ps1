function Push-AuditLogProcessingBatchV2 {
    <#
    .SYNOPSIS
        QueueFunction for the per-tenant V2 processing orchestrator. Builds processing batches from a
        single tenant's CacheWebhooks rows.
    .DESCRIPTION
        Tenant-scoped variant of Push-AuditLogProcessingBatch. Pages the CacheWebhooks rows for the
        tenant supplied via the QueueFunction Parameters, claims unclaimed (or stale > 2h) rows by
        stamping CippProcessing = true, and returns 500-row batch items routed to the
        AuditLogTenantProcessV2 activity (which runs Test-CIPPAuditLogRules and advances the ledger).
        Scoping to one tenant avoids cross-tenant scans and claim races when many tenants process
        concurrently. The 2h stale window lets a crashed processing run be re-claimed and retried.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter ?? $Item.TenantFilter
    if (-not $TenantFilter) {
        Write-Information 'AuditLogProcessingBatchV2: no tenant filter; nothing to process'
        return @()
    }

    $WebhookCacheTable = Get-CippTable -TableName 'CacheWebhooks'
    $AllBatchItems = [System.Collections.Generic.List[object]]::new()
    $NowUtc = (Get-Date).ToUniversalTime()
    $StaleThreshold = $NowUtc.AddHours(-2)

    $Rows = @(Get-CIPPAzDataTableEntity @WebhookCacheTable -Filter "PartitionKey eq '$TenantFilter'" -Property @('PartitionKey', 'RowKey', 'ETag', 'Timestamp', 'CippProcessing'))
    $Claimable = @($Rows | Where-Object {
            -not $_.CippProcessing -or ($_.Timestamp -and $_.Timestamp.UtcDateTime -lt $StaleThreshold)
        })
    if ($Claimable.Count -eq 0) {
        Write-Information "AuditLogProcessingBatchV2: no claimable rows for $TenantFilter"
        return @()
    }

    $RowIds = @($Claimable.RowKey)
    foreach ($Row in $Claimable) {
        Add-CIPPAzDataTableEntity @WebhookCacheTable -Entity ([PSCustomObject]@{
                PartitionKey   = $TenantFilter
                RowKey         = $Row.RowKey
                CippProcessing = $true
            }) -OperationType UpsertMerge
    }

    for ($i = 0; $i -lt $RowIds.Count; $i += 500) {
        $BatchRowIds = $RowIds[$i..([Math]::Min($i + 499, $RowIds.Count - 1))]
        $AllBatchItems.Add([PSCustomObject]@{
                TenantFilter = $TenantFilter
                RowIds       = $BatchRowIds
                FunctionName = 'AuditLogTenantProcessV2'
            })
    }

    if ($AllBatchItems.Count -gt 0) {
        $ProcessQueue = New-CippQueueEntry -Name "Audit Logs Process V2 - $TenantFilter" -Reference 'AuditLogsProcessV2' -TotalTasks $RowIds.Count
        foreach ($BatchItem in $AllBatchItems) {
            $BatchItem | Add-Member -MemberType NoteProperty -Name QueueId -Value $ProcessQueue.RowKey -Force
        }
        Write-Information "AuditLogProcessingBatchV2: $($AllBatchItems.Count) batch item(s) across $($RowIds.Count) row(s) for $TenantFilter"
    }

    return $AllBatchItems.ToArray()
}
