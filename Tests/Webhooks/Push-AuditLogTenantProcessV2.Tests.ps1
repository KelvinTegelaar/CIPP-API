# Pester tests for Push-AuditLogTenantProcessV2 - the audit log V2 processing stage.
#
# One batch item is one SearchId, which is one CacheWebhooks partition (tenant|searchId). The
# invariant these tests exist to protect is that the read stays a SINGLE PARTITION QUERY: an
# OR-list of RowKeys, or a filter on the non-key SearchId column, cannot be served from the Azure
# Table index and degenerates into a partition scan, which is what made processing cost scale with
# the tenant's total backlog rather than the search's own size.
#
# Split records - stored across rows X / X-part1 / X-part2 and only reassembled when every part is
# fetched in one call - still matter, but a partition read gets every part by construction.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $WebhookDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks'

    function Get-CippTable { param($TableName) }
    function Get-AzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    # The plain delete, used by the post-loop partition sweep. Distinct from the CIPP wrapper: the
    # wrapper also removes the -partN rows of split entities, which is what the sweep replaces.
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows, $CachePartitionKey, [switch]$CallerSweepsCachePartition) }

    function Get-WantedFromFilter {
        param([string]$Filter)
        $ids = [regex]::Matches($Filter, "RowKey eq '([^']*)'") | ForEach-Object { $_.Groups[1].Value }
        if ($ids) { @($ids) } else { $null }
    }

    # Real helpers, not mocks: the point-write settle and the quarantined legacy read are part of
    # what these tests are pinning.
    . (Join-Path $WebhookDir 'Set-CippAuditLogWindowProcessed.ps1')
    . (Join-Path $WebhookDir 'Get-CippAuditLogLegacyCacheRow.ps1')
    . (Join-Path $WebhookDir 'Push-AuditLogTenantProcessV2.ps1')
}

Describe 'Push-AuditLogTenantProcessV2' {

    BeforeEach {
        $script:RulesRows = $null
        # AllRulesRows accumulates across slices; RulesRows holds only the last slice.
        $script:AllRulesRows = [System.Collections.Generic.List[object]]::new()
        $script:SeenFilters = [System.Collections.Generic.List[string]]::new()
        # Reads issued by the paging loop only, so assertions about how the search is read are not
        # perturbed by the post-loop sweep, which legitimately queries the same partition again.
        $script:PagingFilters = [System.Collections.Generic.List[string]]::new()
        $script:SweptRows = [System.Collections.Generic.List[object]]::new()
        $script:LedgerWrites = [System.Collections.Generic.List[object]]::new()
        $script:MatchedLogs = 2

        # Physical rows; split records carry OriginalEntityId on every part.
        $script:CacheRows = @(
            [PSCustomObject]@{ RowKey = 'rec-1'; OriginalEntityId = $null; SearchId = 'search-1'; JSON = '{"id":"rec-1"}' }
            [PSCustomObject]@{ RowKey = 'rec-2'; OriginalEntityId = $null; SearchId = 'search-1'; JSON = '{"id":"rec-2"}' }
        )
        $script:LedgerRows = @(
            [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'window-1'; SearchId = 'search-1'; State = 'Downloaded' }
        )
        $script:RemovedRows = [System.Collections.Generic.List[object]]::new()

        # Real Get-CippTable returns only @{ Context = ... }; mirror that so splatting @Table
        # behaves as it does in production.
        Mock -CommandName Get-CippTable -MockWith { param($TableName) @{ Context = "ctx:$TableName" } }

        Mock -CommandName Get-AzDataTableEntity -MockWith {
            param($Context, $Filter, $Property, $First)
            $script:SeenFilters.Add([string]$Filter)
            $rows = $script:CacheRows
            $wanted = Get-WantedFromFilter -Filter $Filter
            if ($wanted) { $rows = @($rows | Where-Object { $wanted -contains $_.RowKey }) }
            # Echo back the partition that was queried rather than a fixed one. This mock serves
            # both the legacy read (tenant partition) and the post-loop sweep (tenant|searchId), and
            # the caller deletes using the PartitionKey it gets back - so a hardcoded value would
            # have the sweep issuing deletes against the wrong partition and still passing.
            $partition = if ($Filter -match "PartitionKey eq '([^']*)'") { $Matches[1] } else { 'contoso.com' }
            @($rows | Sort-Object RowKey) | ForEach-Object {
                [PSCustomObject]@{ PartitionKey = $partition; RowKey = $_.RowKey; OriginalEntityId = $_.OriginalEntityId }
            }
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter, $Property, $First)
            $script:SeenFilters.Add([string]$Filter)
            if ($Context -like '*AuditLogCoverage*') { return $script:LedgerRows }
            $script:PagingFilters.Add([string]$Filter)

            # CacheWebhooks. A partition query carries no RowKey/OriginalEntityId predicates and
            # therefore returns the whole partition - which is the point of the layout.
            $wantedRow = Get-WantedFromFilter -Filter $Filter
            $wantedOrig = @([regex]::Matches($Filter, "OriginalEntityId eq '([^']*)'") | ForEach-Object { $_.Groups[1].Value })
            $rows = if ($wantedRow -or $wantedOrig) {
                @($script:CacheRows | Where-Object {
                        ($wantedRow -contains $_.RowKey) -or
                        ($_.OriginalEntityId -and $wantedOrig -contains $_.OriginalEntityId)
                    })
            } else {
                @($script:CacheRows)
            }
            # rejoin parts sharing a logical id, exactly like the real wrapper
            $merged = @($rows | Group-Object { if ($_.OriginalEntityId) { $_.OriginalEntityId } else { $_.RowKey } } | ForEach-Object {
                    $ordered = @($_.Group | Sort-Object RowKey)
                    [PSCustomObject]@{
                        PartitionKey = 'contoso.com|search-1'
                        RowKey       = $_.Name
                        SearchId     = $ordered[0].SearchId
                        JSON         = ($ordered.JSON -join '')
                    }
                })

            # Honour the paging contract, or the multi-page test silently exercises nothing:
            # rows come back in RowKey order, `RowKey gt` skips what the cursor has passed, and
            # -First caps the page. A mock that ignores these makes an infinite paging loop look
            # like a passing test.
            $merged = @($merged | Sort-Object RowKey)
            if ($Filter -match "RowKey gt '([^']*)'") {
                $after = $Matches[1]
                $merged = @($merged | Where-Object { $_.RowKey -gt $after })
            }
            if ($First) { $merged = @($merged | Select-Object -First $First) }
            $merged
        }

        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity, [switch]$Force, $OperationType)
            $script:LedgerWrites.Add($Entity)
        }

        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity, [switch]$Force)
            foreach ($Removed in @($Entity)) { $script:RemovedRows.Add($Removed) }
        }

        Mock -CommandName Remove-AzDataTableEntity -MockWith {
            param($Context, $Entity, [switch]$Force)
            foreach ($Removed in @($Entity)) { $script:SweptRows.Add($Removed) }
        }

        Mock -CommandName Test-CIPPAuditLogRules -MockWith {
            param($TenantFilter, $Rows)
            $script:RulesRows = @($Rows)
            foreach ($r in @($Rows)) { $script:AllRulesRows.Add($r) }
            [PSCustomObject]@{ MatchedLogs = $script:MatchedLogs }
        }

        $script:Item = @{ TenantFilter = 'contoso.com'; SearchId = 'search-1'; WindowRowKey = 'window-1' }
    }

    Context 'reading one search' {

        It 'passes every cached record to the rules engine' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            @($script:RulesRows).Count | Should -Be 2
            ($script:RulesRows.id | Sort-Object) | Should -Be @('rec-1', 'rec-2')
        }

        It 'deserialises the cached JSON before handing it over' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            @($script:RulesRows)[0].id | Should -Not -BeNullOrEmpty
        }

        It 'returns true on success' {
            Push-AuditLogTenantProcessV2 -Item $script:Item | Should -BeTrue
        }

        It 'reads the search partition, never an OR-list of RowKeys' {
            # The whole point of the layout. An OR-list cannot use the index and scans the
            # partition, which is what made cost scale with the tenant's backlog.
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            $cacheFilters = @($script:SeenFilters | Where-Object { $_ -notmatch 'State eq' })
            $cacheFilters | Should -Contain "PartitionKey eq 'contoso.com|search-1'"
            ($cacheFilters -join ' ') | Should -Not -Match "RowKey eq '"
        }

        It 'never probes the cache by SearchId' {
            # SearchId is not a key; filtering on it is a partition scan. The batch item carries
            # the window RowKey precisely so this lookup is unnecessary.
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            ($script:SeenFilters -join ' ') | Should -Not -Match 'SearchId eq'
        }
    }

    Context 'settling the ledger window' {

        It 'marks the window Processed with the matched count' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            $processed = $script:LedgerWrites | Where-Object { $_.State -eq 'Processed' -and $_.RowKey -eq 'window-1' }
            $processed | Should -Not -BeNullOrEmpty
            $processed.MatchedCount | Should -Be 2
        }

        It 'addresses the window by RowKey rather than searching for it' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            $processed = @($script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' })
            $processed.Count | Should -Be 1
            $processed[0].PartitionKey | Should -Be 'contoso.com'
        }

        It 'settles an already-drained search instead of reporting failure' {
            # A retry after a crash between draining the rows and settling the window. The work
            # is done, so this is success, not an error to be retried forever.
            $script:CacheRows = @()
            Push-AuditLogTenantProcessV2 -Item $script:Item | Should -BeTrue
            ($script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' -and $_.State -eq 'Processed' }) |
                Should -Not -BeNullOrEmpty
            Should -Invoke Test-CIPPAuditLogRules -Times 0
        }

        It 'returns the window to Downloaded when processing throws' {
            Mock -CommandName Test-CIPPAuditLogRules -MockWith { throw 'boom' }
            Push-AuditLogTenantProcessV2 -Item $script:Item | Should -BeFalse
            ($script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' -and $_.State -eq 'Downloaded' }) |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'a malformed batch item' {
        It 'returns false when given neither a SearchId nor legacy row ids' {
            Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com' } | Should -BeFalse
            Should -Invoke Test-CIPPAuditLogRules -Times 0
        }
    }

    Context 'unparseable cache rows (ghosts)' {
        BeforeEach {
            # A ghost row: a shell with no JSON, as left behind by an upserting claim stamp racing
            # a delete. It must be removed, not skipped in place - skipped rows re-enter every
            # claim cycle and keep the tenant's processing loop alive forever.
            $script:CacheRows = @(
                [PSCustomObject]@{ RowKey = 'rec-1'; OriginalEntityId = $null; SearchId = 'search-1'; JSON = '{"id":"rec-1"}' }
                [PSCustomObject]@{ RowKey = 'ghost-1'; OriginalEntityId = $null; SearchId = $null; JSON = $null }
                [PSCustomObject]@{ RowKey = 'garbled-1'; OriginalEntityId = $null; SearchId = 'search-1'; JSON = '{not json' }
            )
        }

        It 'deletes rows whose JSON cannot be parsed' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            ($script:RemovedRows.RowKey | Sort-Object) | Should -Be @('garbled-1', 'ghost-1')
        }

        It 'still processes the parseable rows of the same search' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            @($script:RulesRows).Count | Should -Be 1
            @($script:RulesRows)[0].id | Should -Be 'rec-1'
        }

        It 'deletes ghosts even when every row is unparseable' {
            $script:CacheRows = @(
                [PSCustomObject]@{ RowKey = 'ghost-1'; OriginalEntityId = $null; SearchId = $null; JSON = $null }
                [PSCustomObject]@{ RowKey = 'ghost-2'; OriginalEntityId = $null; SearchId = $null; JSON = $null }
            )
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            ($script:RemovedRows.RowKey | Sort-Object) | Should -Be @('ghost-1', 'ghost-2')
            Should -Invoke Test-CIPPAuditLogRules -Times 0
        }
    }

    Context 'a record split across multiple rows' {
        BeforeEach {
            # One logical record stored across three physical rows. All parts share the search's
            # partition, so a partition read gets every part in one call by construction - the
            # two-phase OriginalEntityId lookup the old per-RowKey read needed is unnecessary.
            $script:CacheRows = @(
                [PSCustomObject]@{ RowKey = 'rec-1'; OriginalEntityId = $null; SearchId = 'search-1'; JSON = '{"id":"rec-1"}' }
                [PSCustomObject]@{ RowKey = 'big'; OriginalEntityId = 'big'; SearchId = 'search-1'; JSON = '{"id":"big","pad":"AAA' }
                [PSCustomObject]@{ RowKey = 'big-part1'; OriginalEntityId = 'big'; SearchId = 'search-1'; JSON = 'BBB' }
                [PSCustomObject]@{ RowKey = 'big-part2'; OriginalEntityId = 'big'; SearchId = 'search-1'; JSON = 'CCC"}' }
            )
        }

        It 'reassembles the split record into valid JSON' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            $big = @($script:RulesRows) | Where-Object { $_.id -eq 'big' }
            $big | Should -Not -BeNullOrEmpty
            $big.pad | Should -Be 'AAABBBCCC'
        }

        It 'yields the split record exactly once, not once per physical row' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            @($script:RulesRows).Count | Should -Be 2
            @($script:RulesRows | Where-Object { $_.id -eq 'big' }).Count | Should -Be 1
        }
    }

    Context 'a search larger than one slice' {
        BeforeEach {
            # 1200 rows against a slice size of 500 forces three passes. Smaller fixtures only
            # execute the loop body once, hiding any off-by-one in the slice arithmetic.
            $script:CacheRows = @(
                1..1200 | ForEach-Object {
                    [PSCustomObject]@{
                        RowKey           = ('rec-{0:D4}' -f $_)
                        OriginalEntityId = $null
                        SearchId         = 'search-1'
                        JSON             = ('{{"id":"rec-{0:D4}"}}' -f $_)
                    }
                }
            )
        }

        It 'processes every row across all slices exactly once' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            @($script:AllRulesRows).Count | Should -Be 1200
            (@($script:AllRulesRows).id | Sort-Object -Unique).Count | Should -Be 1200
        }

        It 'invokes the rules engine once per slice, not once per record' {
            # 1200 / 500 = 3 calls. Slicing is what bounds peak parsed memory; calling per record
            # would instead re-read the rule configuration 1200 times.
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            Should -Invoke Test-CIPPAuditLogRules -Times 3 -Exactly
        }

        It 'still reads the search with a single query regardless of size' {
            # Paging reads only. The post-loop sweep queries the same partition again by design,
            # and counting it here would hide a genuine re-read of page one.
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            @($script:PagingFilters | Where-Object { $_ -eq "PartitionKey eq 'contoso.com|search-1'" }).Count |
                Should -Be 1
        }
    }

    Context 'partition sweep after processing' {
        # The rule engine is told the caller sweeps, which lets it drop processed rows with the
        # plain delete rather than the part-aware one - ~2.7x cheaper per row, and 37% of this
        # stage. That trade is only sound if the sweep actually runs and actually clears the
        # partition, so both halves are pinned here.

        It 'tells the rules engine the caller sweeps' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly -ParameterFilter {
                $CallerSweepsCachePartition -eq $true -and $CachePartitionKey -eq 'contoso.com|search-1'
            }
        }

        It 'removes whatever is left in the partition afterwards' {
            # The engine is mocked and deletes nothing, so every seeded row is still there when the
            # sweep runs - standing in for the -partN rows the plain delete leaves behind.
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            ($script:SweptRows.RowKey | Sort-Object) | Should -Be @('rec-1', 'rec-2')
        }

        It 'sweeps the search partition, not the tenant partition' {
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            ($script:SweptRows.PartitionKey | Sort-Object -Unique) | Should -Be @('contoso.com|search-1')
        }

        It 'does not sweep for legacy batches' {
            # Legacy rows share the tenant partition with every other search, so a sweep there
            # would delete records belonging to searches this batch never processed.
            $null = Push-AuditLogTenantProcessV2 -Item @{
                TenantFilter = 'contoso.com'; LegacyRowIds = @('rec-1', 'rec-2')
            }
            $script:SweptRows.Count | Should -Be 0
        }

        It 'does not sweep when paging stopped because the cursor stalled' {
            # A stalled cursor means the range predicate was not honoured and rows may never have
            # reached the rule engine. Deleting them would drop records with no alert ever fired -
            # strictly worse than leaving them for the next cycle.
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($Context, $Filter, $Property, $First)
                $script:SeenFilters.Add([string]$Filter)
                if ($Context -like '*AuditLogCoverage*') { return $script:LedgerRows }
                # Always the same page, whatever the cursor says. A FULL page (500 = the slice
                # size) is required to reach the guard at all: a short page is treated as the last
                # one and the loop exits normally before any cursor check happens.
                @(1..500 | ForEach-Object {
                        [PSCustomObject]@{
                            PartitionKey = 'contoso.com|search-1'; RowKey = ('rec-{0:D4}' -f $_)
                            SearchId = 'search-1'; JSON = ('{{"id":"rec-{0:D4}"}}' -f $_)
                        }
                    })
            }
            $null = Push-AuditLogTenantProcessV2 -Item $script:Item
            $script:SweptRows.Count | Should -Be 0
        }
    }

    Context 'legacy rows written before per-search partitioning' {
        It 'still processes rows addressed by id from the old tenant partition' {
            $null = Push-AuditLogTenantProcessV2 -Item @{
                TenantFilter = 'contoso.com'; LegacyRowIds = @('rec-1', 'rec-2')
            }
            @($script:RulesRows).Count | Should -Be 2
        }

        It 'keeps the legacy filter short enough to stay inside the request size limit' {
            # Azure rejects ~27kb of filter with HTTP 414 and Azurite ~13kb with HTTP 431, and the
            # outer catch swallows both. Only the legacy path builds filters this way.
            $script:CacheRows = @(
                1..250 | ForEach-Object {
                    [PSCustomObject]@{
                        RowKey = ('rec-{0:D3}' -f $_); OriginalEntityId = $null
                        SearchId = 'search-1'; JSON = ('{{"id":"rec-{0:D3}"}}' -f $_)
                    }
                }
            )
            $ids = @(1..250 | ForEach-Object { 'rec-{0:D3}' -f $_ })
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; LegacyRowIds = $ids }
            ($script:SeenFilters | Measure-Object -Property Length -Maximum).Maximum | Should -BeLessThan 11000
        }
    }
}
