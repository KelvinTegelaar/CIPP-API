# Pester tests for Push-AuditLogDownloadV2 - the audit log V2 download stage.
#
# Pins the ledger state machine and the CacheWebhooks writes. Record order is deliberately
# not asserted; nothing downstream depends on it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogDownloadV2.ps1'

    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First, $Skip, $Sort, $Count) }
    # -Force must be [switch]: as a plain parameter the caller's trailing -Force binds no
    # argument, and the resulting error is swallowed by the function's own catch.
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function New-GraphBulkRequest { param($Requests, $AsApp, $TenantId) }
    function Get-CippAuditLogSearchResults { param($TenantFilter, $QueryId, [switch]$CountOnly) }
    function Get-CippAuditLogNextAttempt { param($Attempts) }

    function New-AuditRecord {
        param([string]$Id, [string]$Created = '2026-07-29T09:00:00Z')
        [pscustomobject]@{
            id              = $Id
            createdDateTime = $Created
            operation       = 'Set-Mailbox'
            auditData       = [pscustomobject]@{ ResultStatus = 'Success' }
        }
    }

    . $FunctionPath
}

Describe 'Push-AuditLogDownloadV2' {

    BeforeEach {
        $script:CacheWrites = [System.Collections.Generic.List[object]]::new()
        # One entry per Add-CIPPAzDataTableEntity call, holding that call's entities. The download
        # stage writes in batches, so the number of calls and the number of rows are different
        # things and both are worth pinning: rows for correctness, calls for the batching itself.
        $script:CacheWriteBatches = [System.Collections.Generic.List[object]]::new()
        $script:LedgerWrites = [System.Collections.Generic.List[object]]::new()
        $script:SearchResults = @()
        $script:SearchStatus = 'succeeded'
        $script:ThrowOnDownload = $false

        Mock -CommandName Get-CippTable -MockWith {
            param($TableName)
            @{ TableName = $TableName }
        }

        # one ledger row in state Created, due now
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                [pscustomobject]@{
                    PartitionKey = 'contoso.com'
                    RowKey       = 'window-1'
                    State        = 'Created'
                    SearchId     = 'search-1'
                    CreatedUtc   = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')
                    Attempts     = 0
                    RetryCount   = 0
                }
            )
        }

        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Entity, $Force, $OperationType)
            if ($TableName -eq 'CacheWebhooks') {
                $Batch = @($Entity)
                $script:CacheWriteBatches.Add($Batch)
                foreach ($Row in $Batch) { $script:CacheWrites.Add($Row) }
            } else { $script:LedgerWrites.Add($Entity) }
        }

        Mock -CommandName New-GraphBulkRequest -MockWith {
            @([pscustomobject]@{ body = [pscustomobject]@{ id = 'search-1'; status = $script:SearchStatus } })
        }

        Mock -CommandName Get-CippAuditLogSearchResults -MockWith {
            if ($script:ThrowOnDownload) { throw 'graph exploded' }
            $script:SearchResults
        }

        Mock -CommandName Get-CippAuditLogNextAttempt -MockWith { (Get-Date).ToUniversalTime().AddMinutes(10).ToString('o') }
    }

    Context 'succeeded search with records' {
        BeforeEach {
            $script:SearchResults = @(New-AuditRecord 'rec-1'), (New-AuditRecord 'rec-2'), (New-AuditRecord 'rec-3')
        }

        It 'writes one CacheWebhooks row per record' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheWrites.Count | Should -Be 3
        }

        It 'keys each cache row by the record id and stores the record as JSON' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            ($script:CacheWrites.RowKey | Sort-Object) | Should -Be @('rec-1', 'rec-2', 'rec-3')
            $first = $script:CacheWrites | Where-Object { $_.RowKey -eq 'rec-1' }
            $first.SearchId | Should -Be 'search-1'
            ($first.JSON | ConvertFrom-Json).id | Should -Be 'rec-1'
            $first.CippProcessing | Should -BeFalse
        }

        It 'partitions the cache per search, not per tenant' {
            # Azure Table only point-looks-up a single PartitionKey+RowKey pair, so a per-tenant
            # partition forces the processing stage to select rows with an OR-list of RowKeys -
            # which cannot use the index and scans. One partition per search keeps every read in
            # the processing path a point-partition query.
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $first = $script:CacheWrites | Where-Object { $_.RowKey -eq 'rec-1' }
            $first.PartitionKey | Should -Be 'contoso.com|search-1'
            $first.TenantFilter | Should -Be 'contoso.com'
        }

        It 'advances the ledger to Downloaded with the record count' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $ledger = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' } | Select-Object -Last 1
            $ledger.State | Should -Be 'Downloaded'
            $ledger.RecordCount | Should -Be 3
            $ledger.Attempts | Should -Be 0
        }

        It 'reports the downloaded count in its result' {
            $result = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $result.Success | Should -BeTrue
            $result.Downloaded | Should -Be 3
        }
    }

    Context 'batched cache writes' {
        # The stage used to issue one table round trip per record. Every record in a window shares
        # the tenant|searchId partition, so they are batchable, and the table service caps a
        # transaction at 100 entities sharing a PartitionKey.

        It 'writes a 250-record window in 3 calls, not 250' {
            $script:SearchResults = @(1..250 | ForEach-Object { New-AuditRecord "rec-$_" })
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheWrites.Count | Should -Be 250
            $script:CacheWriteBatches.Count | Should -Be 3
        }

        It 'never exceeds the 100-entity transaction limit' {
            $script:SearchResults = @(1..250 | ForEach-Object { New-AuditRecord "rec-$_" })
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            foreach ($Batch in $script:CacheWriteBatches) { @($Batch).Count | Should -BeLessOrEqual 100 }
        }

        It 'flushes a trailing partial batch' {
            # 120 records is one full batch plus a remainder; without the post-loop flush the last
            # 20 would be counted as downloaded and the window marked Downloaded, but never written
            # - the search would then settle with rows that do not exist.
            $script:SearchResults = @(1..120 | ForEach-Object { New-AuditRecord "rec-$_" })
            $result = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheWrites.Count | Should -Be 120
            $script:CacheWriteBatches.Count | Should -Be 2
            $result.Downloaded | Should -Be 120
            ($script:CacheWrites.RowKey | Sort-Object -Unique).Count | Should -Be 120
        }

        It 'keeps every batch within a single partition' {
            # A transaction spanning two PartitionKeys is rejected outright, so a buffer shared
            # across windows would fail the whole download rather than degrade.
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                @(
                    [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'window-1'; State = 'Created'; SearchId = 'search-1'; CreatedUtc = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o'); Attempts = 0; RetryCount = 0 }
                    [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'window-2'; State = 'Created'; SearchId = 'search-2'; CreatedUtc = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o'); Attempts = 0; RetryCount = 0 }
                )
            }
            Mock -CommandName New-GraphBulkRequest -MockWith {
                @(
                    [pscustomobject]@{ body = [pscustomobject]@{ id = 'search-1'; status = 'succeeded' } }
                    [pscustomobject]@{ body = [pscustomobject]@{ id = 'search-2'; status = 'succeeded' } }
                )
            }
            # Deliberately not a multiple of the flush size, so window 1 ends mid-buffer and a
            # buffer that outlived the window would carry rows into window 2's batch.
            Mock -CommandName Get-CippAuditLogSearchResults -MockWith {
                param($TenantFilter, $QueryId, [switch]$CountOnly)
                1..150 | ForEach-Object { New-AuditRecord "$QueryId-rec-$_" }
            }

            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }

            $script:CacheWrites.Count | Should -Be 300
            foreach ($Batch in $script:CacheWriteBatches) {
                (@($Batch).PartitionKey | Sort-Object -Unique).Count | Should -Be 1
            }
            (@($script:CacheWrites | Where-Object { $_.PartitionKey -eq 'contoso.com|search-1' }).Count) | Should -Be 150
            (@($script:CacheWrites | Where-Object { $_.PartitionKey -eq 'contoso.com|search-2' }).Count) | Should -Be 150
        }
    }

    Context 'succeeded search with no records' {
        BeforeEach { $script:SearchResults = @() }

        It 'marks an empty window Processed rather than leaving it Downloaded' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $ledger = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' } | Select-Object -Last 1
            $ledger.State | Should -Be 'Processed'
            $ledger.RecordCount | Should -Be 0
            $ledger.MatchedCount | Should -Be 0
        }

        It 'writes no cache rows' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheWrites.Count | Should -Be 0
        }
    }

    Context 'single record' {
        # Guards the PowerShell unrolling trap: one item must still count as a collection.
        BeforeEach { $script:SearchResults = @(New-AuditRecord 'only-1') }

        It 'writes exactly one cache row and counts it as one' {
            $result = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheWrites.Count | Should -Be 1
            $result.Downloaded | Should -Be 1
            $ledger = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' } | Select-Object -Last 1
            $ledger.State | Should -Be 'Downloaded'
            $ledger.RecordCount | Should -Be 1
        }
    }

    Context 'download throws' {
        BeforeEach { $script:ThrowOnDownload = $true }

        It 'increments Attempts and schedules a retry without dead-lettering' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $ledger = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' } | Select-Object -Last 1
            $ledger.Attempts | Should -Be 1
            $ledger.State | Should -BeNullOrEmpty
            $ledger.NextAttemptUtc | Should -Not -BeNullOrEmpty
            $ledger.LastError | Should -Match 'graph exploded'
        }

        It 'still reports success for the activity as a whole' {
            $result = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $result.Success | Should -BeTrue
            $result.Downloaded | Should -Be 0
        }
    }

    Context 'graph reports the search failed' {
        BeforeEach { $script:SearchStatus = 'failed' }

        It 're-plans the window and clears the search id' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $ledger = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' } | Select-Object -Last 1
            $ledger.State | Should -Be 'Planned'
            $ledger.SearchId | Should -Be ''
            $ledger.Attempts | Should -Be 1
        }
    }

    Context 'search still running' {
        BeforeEach { $script:SearchStatus = 'running' }

        It 'leaves the window Created and records the live status' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $ledger = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' } | Select-Object -Last 1
            $ledger.State | Should -BeNullOrEmpty
            $ledger.SearchStatus | Should -Be 'running'
        }

        It 'writes no cache rows' {
            $null = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheWrites.Count | Should -Be 0
        }
    }

    Context 'no due ledger rows' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() }
        }

        It 'returns early without polling graph' {
            $result = Push-AuditLogDownloadV2 -Item @{ TenantFilter = 'contoso.com' }
            $result.Success | Should -BeTrue
            $result.Downloaded | Should -Be 0
            Should -Invoke New-GraphBulkRequest -Times 0
        }
    }
}
