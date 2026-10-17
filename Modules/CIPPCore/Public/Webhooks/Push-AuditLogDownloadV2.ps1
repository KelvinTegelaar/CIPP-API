function Push-AuditLogDownloadV2 {
    <#
    .SYNOPSIS
        Per-tenant audit-log download activity (V2). Polls created searches, downloads succeeded ones
        to CacheWebhooks, advances the AuditLogCoverage ledger and starts processing when there is any.
    .DESCRIPTION
        For the tenant's ledger rows in state 'Created' (and due):
          * bulk-poll Graph search status
          * succeeded  -> download records to CacheWebhooks, mark Downloaded (+ RecordCount)
          * failed     -> re-plan a fresh search (State = Planned, clear SearchId); dead-letter at cap
          * running/notStarted -> leave Created; if stuck > 4h, re-plan
          * download error -> increment Attempts + backoff; dead-letter at cap (NOT terminal)

        Records whose operation no rule for the tenant can match are not stored; a window left with
        none is Processed straight away.
        Processing is started from here only when a window is Downloaded, this run or left over from
        an earlier one, so an empty or unready window costs no further orchestration.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $MaxAttempts = 6
    $StuckHours = 4
    $Downloaded = 0
    # The Azure Table transaction limit. Records are written in batches of this size rather than
    # one at a time; see the download branch below.
    $CacheFlushSize = 100

    try {
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Now = (Get-Date).ToUniversalTime()
        $Active = @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantFilter' and (State eq 'Created' or State eq 'Downloaded' or State eq 'Processing')")
        # Windows downloaded earlier and not yet processed, or a processing run that died (the claim reclaims after 2 h).
        $Stale = $Now.AddHours(-2)
        $PendingProcessing = @($Active.Where({ $_.State -eq 'Downloaded' -or ($_.State -eq 'Processing' -and $_.Timestamp -and $_.Timestamp.UtcDateTime -lt $Stale) })).Count
        $Rows = @($Active.Where({ $_.State -eq 'Created' -and (-not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now) }))

        # Bulk-poll Graph search status for this tenant's created searches
        $Requests = foreach ($Row in $Rows) {
            if ($Row.SearchId) { @{ id = [string]$Row.SearchId; url = "security/auditLog/queries/$($Row.SearchId)"; method = 'GET' } }
        }
        $Requests = @($Requests)
        $StatusById = @{}
        if ($Requests.Count -gt 0) {
            $Responses = New-GraphBulkRequest -Requests $Requests -AsApp $true -TenantId $TenantFilter
            foreach ($Response in $Responses) {
                if ($Response.body -and $Response.body.id) { $StatusById[[string]$Response.body.id] = [string]$Response.body.status }
            }
        }

        $CacheTable = Get-CippTable -TableName 'CacheWebhooks'
        $OperationFilter = $null
        $FilterLoaded = $false

        foreach ($Row in $Rows) {
            $SearchId = [string]$Row.SearchId
            $Status = $StatusById[$SearchId]
            $CreatedAgeHours = if ($Row.CreatedUtc) { ($Now - ([datetimeoffset]$Row.CreatedUtc).UtcDateTime).TotalHours } else { 999 }

            if ($Status -eq 'succeeded') {
                try {
                    if (-not $FilterLoaded) {
                        # The operations the tenant's rules can match, or $null when a rule can match any operation.
                        # Culture-aware like the engine's -eq/-in, which ignores characters such as a trailing U+200B.
                        $OperationFilter = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
                        foreach ($Rule in (Get-CIPPAuditLogRuleSet -TenantFilter $TenantFilter)) {
                            if ($TenantFilter -in $Rule.Excluded.value) { continue }
                            $Conditions = @($Rule.Conditions | ConvertFrom-Json -ErrorAction SilentlyContinue | Where-Object { $_.Input.value -ne '' })
                            $OperationValues = @(foreach ($Condition in $Conditions) {
                                    if ($Condition.Property.label -eq 'Operation' -and [string]$Condition.Operator.value -in @('eq', 'in')) { $Condition.Input.value }
                                })
                            if ($Conditions.Count -gt 0 -and $OperationValues.Count -eq 0) {
                                $OperationFilter = $null
                                break
                            }
                            foreach ($Value in $OperationValues) { [void]$OperationFilter.Add([string]$Value) }
                        }
                        $FilterLoaded = $true
                    }
                    # Streamed, not collected: each record is written to CacheWebhooks and
                    # dropped, so the window never needs to be resident.
                    # tenant|search, not tenant: Azure Table only point-looks-up a single
                    # PartitionKey+RowKey pair, so an OR-list of RowKeys inside one big per-tenant
                    # partition scans it. Per-search partitions keep every processing read a point
                    # query. Records in the 5-min window overlap land in both partitions and are
                    # processed twice; alerting still fires once (Invoke-CippWebhookProcessing
                    # claim-inserts AuditLogs[tenant, id] without -Force).
                    $CachePartition = '{0}|{1}' -f $TenantFilter, $SearchId

                    # Buffered rather than one write per record. The table service takes
                    # transactions of up to 100 entities that share a PartitionKey, and every record
                    # in a window shares tenant|searchId by construction, so the single-entity write
                    # was paying one round trip per record for nothing: 2,608 ms/1k against
                    # 181 ms/1k batched on identical payloads, ~70% of this stage's cost.
                    # The buffer lives inside the per-window branch, so a batch can never straddle
                    # two partitions - the service rejects a transaction that does.
                    $WindowCount = 0
                    $StoredCount = 0
                    $Buffer = [System.Collections.Generic.List[object]]::new()
                    Get-CippAuditLogSearchResults -TenantFilter $TenantFilter -QueryId $SearchId | ForEach-Object {
                        $WindowCount++
                        if ($null -ne $OperationFilter -and -not $OperationFilter.Contains([string]($_.auditData.Operation ?? $_.operation))) { return }
                        $Buffer.Add(@{
                                RowKey                = [string]$_.id
                                PartitionKey          = [string]$CachePartition
                                TenantFilter          = [string]$TenantFilter
                                SearchId              = $SearchId
                                # -InputObject rather than a pipeline: same output, but it skips
                                # building a pipeline per record. Measured at 75 us against 43 us
                                # for a record of this shape, and this runs once per record.
                                JSON                  = [string](ConvertTo-Json -InputObject $_ -Depth 10 -Compress)
                                CippProcessing        = $false
                                CippProcessingStarted = ''
                            })
                        $StoredCount++
                        # Flushing mid-stream keeps peak memory at one batch rather than the whole
                        # window, and leaves a failure having made forward progress. Re-downloading
                        # after a retry rewrites flushed records, which is a no-op: the write is an
                        # upsert keyed by record id.
                        if ($Buffer.Count -ge $CacheFlushSize) {
                            Add-CIPPAzDataTableEntity @CacheTable -Entity $Buffer.ToArray() -Force
                            $Buffer.Clear()
                        }
                    }
                    if ($Buffer.Count -gt 0) {
                        Add-CIPPAzDataTableEntity @CacheTable -Entity $Buffer.ToArray() -Force
                        $Buffer.Clear()
                    }
                    $Downloaded += $StoredCount
                    # Windows with nothing stored have nothing to process - mark them Processed directly so
                    # they don't sit at Downloaded forever. Windows with records go to Downloaded and are
                    # advanced to Processed by Push-AuditLogTenantProcessV2 once their rows are drained.
                    $DownloadState = if ($StoredCount -eq 0) { 'Processed' } else { 'Downloaded' }
                    if ($StoredCount -gt 0) { $PendingProcessing++ }
                    $LedgerUpdate = @{
                        PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = $DownloadState
                        RecordCount  = [int]$WindowCount; CandidateCount = [int]$StoredCount; DownloadedUtc = $Now; Attempts = 0
                        SearchStatus = 'succeeded'; LastPolledUtc = $Now
                    }
                    if ($DownloadState -eq 'Processed') {
                        $LedgerUpdate.ProcessedUtc = $Now
                        $LedgerUpdate.MatchedCount = 0
                    }
                    Add-CIPPAzDataTableEntity @Ledger -Entity $LedgerUpdate -OperationType UpsertMerge
                    Write-Information "AuditLogV2: downloaded $WindowCount record(s), stored $StoredCount, for $TenantFilter window $($Row.RowKey)"
                } catch {
                    $Attempts = [int]$Row.Attempts + 1
                    $RetryTotal = [int]$Row.RetryCount + 1
                    if ($Attempts -ge $MaxAttempts) {
                        Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'DeadLetter'; Attempts = $Attempts; RetryCount = $RetryTotal; LastError = [string]$_.Exception.Message; LastErrorUtc = $Now } -OperationType UpsertMerge
                    } else {
                        Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; Attempts = $Attempts; RetryCount = $RetryTotal; NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts $Attempts); LastError = [string]$_.Exception.Message; LastErrorUtc = $Now } -OperationType UpsertMerge
                    }
                    Write-Information "AuditLogV2: download error for $TenantFilter window $($Row.RowKey): $($_.Exception.Message)"
                }
            } elseif ($Status -eq 'failed') {
                $Attempts = [int]$Row.Attempts + 1
                $RetryTotal = [int]$Row.RetryCount + 1
                if ($Attempts -ge $MaxAttempts) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'DeadLetter'; Attempts = $Attempts; RetryCount = $RetryTotal; SearchStatus = 'failed'; LastPolledUtc = $Now; LastError = 'Graph search failed'; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; SearchId = ''; Attempts = $Attempts; RetryCount = $RetryTotal; SearchStatus = ''; LastPolledUtc = $Now; NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts $Attempts); LastError = 'Graph search failed; re-planning'; LastErrorUtc = $Now } -OperationType UpsertMerge
                }
            } elseif ($Status -in @('running', 'notStarted')) {
                if ($CreatedAgeHours -ge $StuckHours) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; SearchId = ''; SearchStatus = ''; LastPolledUtc = $Now; RetryCount = ([int]$Row.RetryCount + 1); LastError = 'Search stuck; re-planning'; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    # Not ready yet: leave Created, but persist the live Graph search status so a pending
                    # window shows WHY it is still in-flight (e.g. 'running') rather than looking stuck.
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; SearchStatus = [string]$Status; LastPolledUtc = $Now } -OperationType UpsertMerge
                }
            } else {
                # Unknown / search no longer present on Graph
                if ($CreatedAgeHours -ge $StuckHours) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; SearchId = ''; SearchStatus = ''; LastPolledUtc = $Now; RetryCount = ([int]$Row.RetryCount + 1); LastError = 'Search not found; re-planning'; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; SearchStatus = $(if ($Status) { [string]$Status } else { 'unknown' }); LastPolledUtc = $Now } -OperationType UpsertMerge
                }
            }
        }

        if ($PendingProcessing -gt 0) {
            # Push-AuditLogProcessingBatchV2 claims the Downloaded windows and returns nothing when another run holds them.
            Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                    OrchestratorName = "AuditLogProcessV2-$TenantFilter"
                    QueueFunction    = [PSCustomObject]@{ FunctionName = 'AuditLogProcessingBatchV2'; Parameters = @{ TenantFilter = $TenantFilter } }
                    SkipLog          = $true
                    Priority         = 3
                })
        }
        return @{ TenantFilter = $TenantFilter; Success = $true; Downloaded = $Downloaded }
    } catch {
        Write-Information ('Push-AuditLogDownloadV2 error for {0}: {1}' -f $TenantFilter, $_.Exception.Message)
        return @{ TenantFilter = $TenantFilter; Success = $false; Downloaded = $Downloaded; Error = $_.Exception.Message }
    }
}
