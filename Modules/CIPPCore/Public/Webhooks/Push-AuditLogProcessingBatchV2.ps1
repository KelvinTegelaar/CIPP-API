function Push-AuditLogProcessingBatchV2 {
    <#
    .SYNOPSIS
        QueueFunction for the per-tenant V2 processing orchestrator. Emits one batch item per
        downloaded search.
    .DESCRIPTION
        Claims work at SEARCH granularity. Each batch item is one SearchId, which is also one
        CacheWebhooks partition, so the consuming activity reads it with a partition query.

        This replaces a per-record claim that read every CacheWebhooks row for the tenant and
        stamped each one - measured at 17.6s of bookkeeping per 5k records before a single record
        was examined. Claiming the AuditLogCoverage row is one write per search instead, and the
        ledger already had a state machine for it.

        A search left in Processing beyond the stale window is reclaimed so a crashed run retries.

        LEGACY: rows written before per-search partitioning live under PartitionKey = <tenant> and
        are picked up by a compatibility pass. CacheWebhooks is transient, so this stops finding
        anything within a cycle or two and can be removed a release later.
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
    $StaleHours = 2

    $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
    $Now = (Get-Date).ToUniversalTime()
    $Stale = $Now.AddHours(-$StaleHours)

    $Rows = @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantFilter'")
    $Claimable = @($Rows | Where-Object {
            $_.SearchId -and (
                $_.State -eq 'Downloaded' -or
                ($_.State -eq 'Processing' -and $_.Timestamp -and $_.Timestamp.UtcDateTime -lt $Stale)
            )
        })

    $BatchItems = [System.Collections.Generic.List[object]]::new()

    # Claim by updating, never upserting: a window row removed by ledger retention while this loop
    # runs must not be resurrected as a stateless shell that re-enters every cycle.
    foreach ($Row in $Claimable) {
        try {
            Update-CIPPAzDataTableEntity @Ledger -Entity ([PSCustomObject]@{
                    PartitionKey = $TenantFilter
                    RowKey       = $Row.RowKey
                    State        = 'Processing'
                })
            $BatchItems.Add([PSCustomObject]@{
                    TenantFilter = $TenantFilter
                    SearchId     = [string]$Row.SearchId
                    WindowRowKey = [string]$Row.RowKey
                    RecordCount  = [int]$Row.RecordCount
                    FunctionName = 'AuditLogTenantProcessV2'
                })
        } catch {
            Write-Information "AuditLogProcessingBatchV2: window $($Row.RowKey) for $TenantFilter vanished before it could be claimed; skipping"
        }
    }

    # --- Legacy: rows still sitting in the old per-tenant partition ---
    # Only reached while an upgrade drains; costs one keys-only read of a partition that is empty
    # on any instance that has already cycled.
    try {
        $CacheTable = Get-CippTable -TableName 'CacheWebhooks'
        $LegacyRows = @(Get-CIPPAzDataTableEntity @CacheTable -Filter "PartitionKey eq '$TenantFilter'" -Property PartitionKey, RowKey)
        if ($LegacyRows.Count -gt 0) {
            Write-Information "AuditLogProcessingBatchV2: $($LegacyRows.Count) legacy pre-partition row(s) for $TenantFilter"
            $LegacyIds = @($LegacyRows.RowKey)
            for ($i = 0; $i -lt $LegacyIds.Count; $i += 500) {
                $BatchItems.Add([PSCustomObject]@{
                        TenantFilter = $TenantFilter
                        LegacyRowIds = @($LegacyIds[$i..([Math]::Min($i + 499, $LegacyIds.Count - 1))])
                        FunctionName = 'AuditLogTenantProcessV2'
                    })
            }
        }
    } catch {
        Write-Information "AuditLogProcessingBatchV2: legacy sweep skipped for ${TenantFilter}: $($_.Exception.Message)"
    }

    if ($BatchItems.Count -eq 0) {
        Write-Information "AuditLogProcessingBatchV2: nothing to process for $TenantFilter"
        return @()
    }

    $TotalRecords = ($Claimable | Measure-Object RecordCount -Sum).Sum
    $ProcessQueue = New-CippQueueEntry -Name "Audit Logs Process V2 - $TenantFilter" -Reference 'AuditLogsProcessV2' -TotalTasks $BatchItems.Count
    foreach ($BatchItem in $BatchItems) {
        $BatchItem | Add-Member -MemberType NoteProperty -Name QueueId -Value $ProcessQueue.RowKey -Force
    }

    Write-Information "AuditLogProcessingBatchV2: $($BatchItems.Count) batch item(s), ~$TotalRecords record(s) for $TenantFilter"
    return $BatchItems.ToArray()
}
