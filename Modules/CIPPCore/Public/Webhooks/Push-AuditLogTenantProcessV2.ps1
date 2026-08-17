function Push-AuditLogTenantProcessV2 {
    <#
    .SYNOPSIS
        Per-search audit-log processing activity (V2). Runs Test-CIPPAuditLogRules over one
        search's cached records and settles its AuditLogCoverage window.
    .DESCRIPTION
        One batch item is one SearchId, which is one CacheWebhooks partition, so a search is read
        with point-partition queries instead of "PartitionKey eq <tenant> and (RowKey eq a or ...)"
        - an OR-list cannot use the index and scans. Reading by partition also removes the second
        pass that resolved OriginalEntityId, since every part of a split record shares the
        partition and the read wrapper reassembles parts arriving in one call.

        The window is settled by point write rather than a "SearchId eq" lookup (also a scan), and
        the old orphaned-window sweep is gone: it only existed because a record returned by two
        overlapping windows had its SearchId overwritten inside a shared tenant partition.

        Overlap records now appear in two partitions and are processed twice; alerting still fires
        once via Invoke-CippWebhookProcessing's claim-insert.

        Accepts LegacyRowIds for rows written before the partitioning change.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $SearchId = $Item.SearchId
    $WindowRowKey = $Item.WindowRowKey
    $LegacyRowIds = $Item.LegacyRowIds

    # Rules are re-read per call by Test-CIPPAuditLogRules, so slice large searches rather than
    # calling it per record - and keep the slice at the old batch size so peak parsed memory is
    # unchanged even though the read is now one partition.
    $SliceSize = 500

    try {
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        $ProcessedCount = 0
        $MatchedLogs = 0

        if (-not $LegacyRowIds -and -not $SearchId) {
            Write-Information "AuditLogV2: batch item for $TenantFilter has neither SearchId nor LegacyRowIds; nothing to do"
            return $false
        }

        $Partition = if ($LegacyRowIds) { $TenantFilter } else { '{0}|{1}' -f $TenantFilter, $SearchId }
        $Poison = [System.Collections.Generic.List[object]]::new()
        $Cursor = $null
        $AnyRows = $false
        # Set when paging stops because the cursor failed to advance. The partition sweep below is
        # skipped in that case: rows may still be unprocessed, and sweeping would delete records
        # that were never run through the rule engine.
        $CursorStalled = $false

        # Paged so peak memory tracks the slice, not the whole search. `RowKey gt <cursor>` is
        # still a point-partition range query. The cursor matters because the rule engine deletes
        # rows as it goes: re-issuing the same query would reshuffle what "next page" means,
        # whereas advancing past the highest RowKey seen is monotonic either way.
        while ($true) {
            if ($LegacyRowIds) {
                # Legacy rows are addressed by id, not range - fetch once and exit after one pass.
                $Entities = @(Get-CippAuditLogLegacyCacheRow -TenantFilter $TenantFilter -RowIds @($LegacyRowIds))
            } else {
                $Filter = if ($Cursor) { "PartitionKey eq '$Partition' and RowKey gt '$Cursor'" } else { "PartitionKey eq '$Partition'" }
                $Entities = @(Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter $Filter -First $SliceSize)
            }
            if ($Entities.Count -eq 0) { break }
            $AnyRows = $true
            $PageCount = $Entities.Count

            # Rows come back in RowKey order within a partition, but sort rather than assume it -
            # a cursor that goes backwards would re-read forever.
            $NextCursor = @($Entities.RowKey | Sort-Object)[-1]

            # Hard guard, checked BEFORE processing: if the cursor did not move, the range
            # predicate was not honoured and this is the previous page served again. Processing it
            # would double-count every record in it. Never rely on the backend alone to terminate a
            # paging loop, and never assume a repeated page is new work.
            if ($null -ne $Cursor -and [string]$NextCursor -le [string]$Cursor) {
                Write-Information "AuditLogV2: cursor did not advance for $TenantFilter search $SearchId; stopping paging"
                $CursorStalled = $true
                break
            }
            $Cursor = $NextCursor

            $Chunk = [System.Collections.Generic.List[object]]::new()

            for ($i = 0; $i -lt $Entities.Count; $i++) {
                $Entity = $Entities[$i]
                if ($null -eq $Entity) { continue }
                # try/catch, not -ErrorAction: ConvertFrom-Json parse failures are terminating, so
                # without the catch one garbled row aborts the whole batch via the outer catch.
                try {
                    # -InputObject rather than a pipeline, once per record. A null JSON column binds
                    # as a terminating error here where the pipeline form simply emitted nothing,
                    # but both land on $Parsed = $null and the poison path below, so the row is
                    # treated identically.
                    $Parsed = ConvertFrom-Json -InputObject $Entity.JSON -ErrorAction Stop
                } catch {
                    $Parsed = $null
                }
                if ($null -eq $Parsed) {
                    # A row whose JSON can never parse can never be drained; left in place it
                    # re-enters every claim cycle forever. Delete it.
                    Write-Information "AuditLogV2: removing unparseable cache row $($Entity.RowKey) ($TenantFilter)"
                    $Poison.Add([PSCustomObject]@{ PartitionKey = [string]$Entity.PartitionKey; RowKey = [string]$Entity.RowKey })
                } else {
                    $Chunk.Add($Parsed)
                }
                # Release the raw row as soon as it is parsed. The entity holds the JSON string and
                # the parsed object holds an expanded copy of the same data; without this both are
                # live at once for the whole page.
                $Entities[$i] = $null
            }

            if ($Chunk.Count -gt 0) {
                # The rule engine deletes the rows it processes, flushing mid-loop so a crash still
                # makes forward progress. It therefore needs the partition those rows actually live
                # in - the cache is keyed tenant|searchId, not tenant. Legacy batches keep the old
                # tenant partition.
                # -CallerSweepsCachePartition lets the engine drop processed rows with the plain
                # delete instead of the part-aware one, which costs ~2.7x per row because it also
                # removes the -partN rows of split entities. The sweep after this loop honours that
                # guarantee. Legacy batches share the tenant partition with other searches and are
                # never swept, so they keep the part-aware delete.
                $SweepArgs = @{}
                if (-not $LegacyRowIds) { $SweepArgs.CallerSweepsCachePartition = $true }
                $Result = Test-CIPPAuditLogRules -TenantFilter $TenantFilter -Rows $Chunk -CachePartitionKey $Partition @SweepArgs
                $MatchedLogs += [int]($Result.MatchedLogs ?? 0)
                $ProcessedCount += $Chunk.Count
            }
            $Chunk.Clear()
            $Chunk = $null
            $Entities = $null

            if ($LegacyRowIds) { break }
            # A short page is the last page - asking again only costs a round trip.
            if ($PageCount -lt $SliceSize) { break }
        }

        if (-not $AnyRows) {
            # Already drained - a retry after a crash between draining and settling.
            if ($WindowRowKey) { Set-CippAuditLogWindowProcessed -TenantFilter $TenantFilter -WindowRowKey $WindowRowKey -MatchedCount 0 }
            Write-Information "AuditLogV2: no cached rows for $TenantFilter search $SearchId"
            return $true
        }

        # Honour the -CallerSweepsCachePartition guarantee. The partition holds exactly this search,
        # so a keys-only pass is a point-partition query and anything it finds belongs to this
        # search alone: -partN rows orphaned by the plain delete, or rows the engine could not
        # drain. Normally it finds nothing and costs one round trip per search.
        # Raw Get-AzDataTableEntity, not the wrapper: the wrapper reassembles split entities and
        # reports the orphaned parts as corrupt rather than returning them, which is the opposite
        # of what a sweep needs - it wants the literal rows, parts included.
        # Skipped when the cursor stalled, because rows may then be unprocessed.
        if ($SearchId -and -not $LegacyRowIds -and -not $CursorStalled) {
            try {
                $Residue = @(Get-AzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$Partition'" -Property PartitionKey, RowKey)
                if ($Residue.Count -gt 0) {
                    $null = Remove-AzDataTableEntity -Force @CacheWebhooksTable -Entity @($Residue | ForEach-Object {
                            [PSCustomObject]@{ PartitionKey = [string]$_.PartitionKey; RowKey = [string]$_.RowKey } })
                    Write-Information "AuditLogV2: swept $($Residue.Count) leftover row(s) from $Partition"
                }
            } catch {
                # Not fatal: leftovers are re-swept next cycle, and the window is already processed.
                Write-Information "AuditLogV2: partition sweep failed for ${Partition}: $($_.Exception.Message)"
            }
        }

        if ($Poison.Count -gt 0) {
            try {
                $null = Remove-CIPPAzDataTableEntity -Force @CacheWebhooksTable -Entity $Poison.ToArray()
            } catch {
                Write-Information "AuditLogV2: failed to remove $($Poison.Count) unparseable row(s) for ${TenantFilter}: $($_.Exception.Message)"
            }
        }

        Write-Information "AuditLogV2: processed $ProcessedCount row(s) for $TenantFilter$(if ($SearchId) { " search $SearchId" })"

        # Point write - the batch owns exactly one window, so there is nothing to search for.
        if ($WindowRowKey) {
            Set-CippAuditLogWindowProcessed -TenantFilter $TenantFilter -WindowRowKey $WindowRowKey -MatchedCount $MatchedLogs
        }

        return $true
    } catch {
        # Back to Downloaded so the next cycle re-claims it; the stale-Processing reclaim in
        # Push-AuditLogProcessingBatchV2 is the backstop if this write is what failed.
        if ($WindowRowKey) {
            try {
                $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
                Add-CIPPAzDataTableEntity @Ledger -Entity @{
                    PartitionKey = $TenantFilter
                    RowKey       = $WindowRowKey
                    State        = 'Downloaded'
                    LastError    = [string]$_.Exception.Message
                    LastErrorUtc = (Get-Date).ToUniversalTime()
                } -OperationType UpsertMerge
            } catch {
                Write-Information "AuditLogV2: could not reset window $WindowRowKey to Downloaded for ${TenantFilter}: $($_.Exception.Message)"
            }
        }
        Write-Information ('Push-AuditLogTenantProcessV2: Error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        return $false
    }
}
