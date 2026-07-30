function Push-AuditLogTenantProcessV2 {
    <#
    .SYNOPSIS
        Per-batch audit-log processing activity (V2). Processes a batch of cached rows via the
        existing Test-CIPPAuditLogRules engine, then advances the AuditLogCoverage ledger to
        'Processed' for any SearchId whose rows are now fully drained from the cache.
    .DESCRIPTION
        Same processing as the V1 Push-AuditLogTenantProcess (reads the RowIds from CacheWebhooks
        and runs Test-CIPPAuditLogRules, which removes processed rows). Additionally:
          * captures the distinct SearchIds represented by this batch's rows
          * after processing, for each of those SearchIds with zero remaining CacheWebhooks rows,
            marks the matching ledger window State = 'Processed' (ProcessedUtc + MatchedCount)
        Because the mark is gated on "no rows left for this SearchId", a search split across
        multiple 500-row batches is only marked Processed when its final batch completes.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $RowIds = $Item.RowIds

    try {
        $CacheWebhooksTable = Get-CippTable -TableName 'CacheWebhooks'
        $SearchIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        # Chunked so peak memory tracks $ChunkSize, not batch size. Don't raise much above
        # 100: each chunk builds one `RowKey eq '<guid>'` predicate per row, and an over-long
        # filter is rejected (Azure ~520 predicates, Azurite ~250) and swallowed by the catch.
        $ChunkSize = 100
        $ProcessedCount = 0
        $MatchedLogs = 0

        for ($Offset = 0; $Offset -lt $RowIds.Count; $Offset += $ChunkSize) {
            $Slice = @($RowIds[$Offset..([Math]::Min($Offset + $ChunkSize - 1, $RowIds.Count - 1))])

            # Raw cmdlet: the wrapper merges split parts and reports the logical RowKey.
            $KeyFilter = "PartitionKey eq '$TenantFilter' and (" +
                         (($Slice | ForEach-Object { "RowKey eq '$_'" }) -join ' or ') + ')'
            $Keys = @(Get-AzDataTableEntity @CacheWebhooksTable -Filter $KeyFilter `
                    -Property 'PartitionKey', 'RowKey', 'OriginalEntityId')
            if ($Keys.Count -eq 0) { continue }

            # Split records span X / X-part1 / X-part2 and only reassemble when every part
            # arrives in one call, so select on OriginalEntityId rather than RowKey.
            $Predicates = [System.Collections.Generic.List[string]]::new()
            $SeenLogical = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Key in $Keys) {
                if ($Key.PSObject.Properties.Name -contains 'OriginalEntityId' -and $Key.OriginalEntityId) {
                    if ($SeenLogical.Add([string]$Key.OriginalEntityId)) {
                        $Predicates.Add("OriginalEntityId eq '$($Key.OriginalEntityId)'")
                    }
                } else {
                    $Predicates.Add("RowKey eq '$($Key.RowKey)'")
                }
            }
            if ($Predicates.Count -eq 0) { continue }

            # No -Property: a projection must list every JSON_Part* column or split rows
            # come back empty.
            $RowFilter = "PartitionKey eq '$TenantFilter' and (" + ($Predicates -join ' or ') + ')'
            $Entities = @(Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter $RowFilter)

            $Chunk = [System.Collections.Generic.List[object]]::new()
            foreach ($Entity in $Entities) {
                if ($Entity.SearchId) { [void]$SearchIds.Add([string]$Entity.SearchId) }
                $Parsed = $Entity.JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($null -eq $Parsed) {
                    Write-Information "AuditLogV2: unparseable cached JSON for RowKey $($Entity.RowKey) ($TenantFilter)"
                    continue
                }
                $Chunk.Add($Parsed)
            }

            if ($Chunk.Count -gt 0) {
                $Result = Test-CIPPAuditLogRules -TenantFilter $TenantFilter -Rows $Chunk
                $MatchedLogs += [int]($Result.MatchedLogs ?? 0)
                $ProcessedCount += $Chunk.Count
            }
            $Chunk.Clear()
            $Entities = $null
        }

        if ($ProcessedCount -eq 0) {
            Write-Information "AuditLogV2: no rows found in cache for the provided row IDs ($TenantFilter)"
            return $false
        }

        Write-Information "AuditLogV2: processed $ProcessedCount row(s) for $TenantFilter"

        # Advance the ledger to Processed for any SearchId now fully drained from the cache.
        if ($SearchIds.Count -gt 0) {
            $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
            $SingleSearch = ($SearchIds.Count -eq 1)
            $Now = (Get-Date).ToUniversalTime()
            foreach ($SearchId in $SearchIds) {
                $Remaining = @(Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'" -Property PartitionKey, RowKey)
                if ($Remaining.Count -gt 0) { continue }

                $LedgerRows = @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$SearchId'")
                foreach ($LedgerRow in $LedgerRows) {
                    $Update = @{
                        PartitionKey = $TenantFilter
                        RowKey       = $LedgerRow.RowKey
                        State        = 'Processed'
                        ProcessedUtc = $Now
                    }
                    # Only attribute matched count when this batch was a single search (unambiguous).
                    if ($SingleSearch) { $Update.MatchedCount = $MatchedLogs }
                    Add-CIPPAzDataTableEntity @Ledger -Entity $Update -OperationType UpsertMerge
                    Write-Information "AuditLogV2: marked window $($LedgerRow.RowKey) Processed for $TenantFilter (search $SearchId)"
                }
            }
        }

        # Sweep orphaned Downloaded windows. Once this batch's rows are processed, re-scan every
        # window left at 'Downloaded' for the tenant and cross-check it against the cache by SearchId.
        # If no CacheWebhooks rows remain for that search, the records were already processed - often
        # under an OVERLAPPING window's search, because CacheWebhooks is keyed by record id, so a 5-min
        # window overlap (or a legacy 60-min window sharing record ids) overwrites the SearchId and the
        # per-batch marking above never sees this window's id. Mark it Processed. Windows whose search
        # still has cache rows are left as-is; they get picked up on the next process round.
        try {
            $SweepLedger = Get-CippTable -TableName 'AuditLogCoverage'
            $SweepNow = (Get-Date).ToUniversalTime()
            $DownloadedRows = @(Get-CIPPAzDataTableEntity @SweepLedger -Filter "PartitionKey eq '$TenantFilter' and State eq 'Downloaded'")
            foreach ($DownRow in $DownloadedRows) {
                $Sid = [string]$DownRow.SearchId
                if (-not $Sid) { continue }
                $Remaining = @(Get-CIPPAzDataTableEntity @CacheWebhooksTable -Filter "PartitionKey eq '$TenantFilter' and SearchId eq '$Sid'" -Property PartitionKey, RowKey)
                if ($Remaining.Count -gt 0) { continue }
                Add-CIPPAzDataTableEntity @SweepLedger -Entity @{
                    PartitionKey = $TenantFilter
                    RowKey       = $DownRow.RowKey
                    State        = 'Processed'
                    ProcessedUtc = $SweepNow
                    MatchedCount = 0
                } -OperationType UpsertMerge
                Write-Information "AuditLogV2: swept window $($DownRow.RowKey) to Processed for $TenantFilter (search $Sid drained, no cache rows)"
            }
        } catch {
            Write-Information ('Push-AuditLogTenantProcessV2 sweep error for {0}: {1}' -f $TenantFilter, $_.Exception.Message)
        }

        return $true
    } catch {
        Write-Information ('Push-AuditLogTenantProcessV2: Error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
        return $false
    }
}
