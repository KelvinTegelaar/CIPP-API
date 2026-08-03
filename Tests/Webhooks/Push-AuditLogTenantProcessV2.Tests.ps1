# Pester tests for Push-AuditLogTenantProcessV2 - the audit log V2 processing stage.
#
# Pins the ledger transitions and the rows handed to the rules engine. The cases that
# matter are split records, stored across rows X / X-part1 / X-part2 and only reassembled
# when every part is fetched in one call.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogTenantProcessV2.ps1'

    function Get-CippTable { param($TableName) }
    function Get-AzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, $OperationType) }
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows) }

    function Get-WantedFromFilter {
        param([string]$Filter)
        $ids = [regex]::Matches($Filter, "RowKey eq '([^']*)'") | ForEach-Object { $_.Groups[1].Value }
        if ($ids) { @($ids) } else { $null }
    }

    . $FunctionPath
}

Describe 'Push-AuditLogTenantProcessV2' {

    BeforeEach {
        $script:RulesRows = $null
        # AllRulesRows accumulates across chunks; RulesRows holds only the last chunk.
        $script:AllRulesRows = [System.Collections.Generic.List[object]]::new()
        $script:SeenFilters = [System.Collections.Generic.List[string]]::new()
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
        $script:RemainingAfterProcess = @()
        $script:DownloadedSweepRows = @()

        # Real Get-CippTable returns only @{ Context = ... }; mirror that so splatting @Table
        # behaves as it does in production.
        Mock -CommandName Get-CippTable -MockWith { param($TableName) @{ Context = "ctx:$TableName" } }

        Mock -CommandName Get-AzDataTableEntity -MockWith {
            param($Context, $Filter, $Property, $First)
            $script:SeenFilters.Add([string]$Filter)
            $rows = $script:CacheRows
            if ($Filter -match "RowKey gt '([^']*)'") { $rows = @($rows | Where-Object { $_.RowKey -gt $Matches[1] }) }
            $wanted = Get-WantedFromFilter -Filter $Filter
            if ($wanted) { $rows = @($rows | Where-Object { $wanted -contains $_.RowKey }) }
            $rows = @($rows | Sort-Object RowKey)
            if ($First) { $rows = @($rows | Select-Object -First $First) }
            $rows | ForEach-Object {
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = $_.RowKey; OriginalEntityId = $_.OriginalEntityId }
            }
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter, $Property, $First)
            if ($Context -like '*AuditLogCoverage*') {
                if ($Filter -match "State eq 'Downloaded'") { return $script:DownloadedSweepRows }
                return $script:LedgerRows
            }
            # CacheWebhooks. A SearchId query is the "is this search drained yet" probe.
            if ($Filter -match "SearchId eq") { return $script:RemainingAfterProcess }

            # Selected by RowKey (simple records) or OriginalEntityId (every part of a split
            # record, regardless of which parts this batch claimed).
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
            $rows | Group-Object { if ($_.OriginalEntityId) { $_.OriginalEntityId } else { $_.RowKey } } | ForEach-Object {
                $ordered = @($_.Group | Sort-Object RowKey)
                [PSCustomObject]@{
                    PartitionKey = 'contoso.com'
                    RowKey       = $_.Name
                    SearchId     = $ordered[0].SearchId
                    JSON         = ($ordered.JSON -join '')
                }
            }
        }

        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity, [switch]$Force, $OperationType)
            $script:LedgerWrites.Add($Entity)
        }

        Mock -CommandName Test-CIPPAuditLogRules -MockWith {
            param($TenantFilter, $Rows)
            $script:RulesRows = @($Rows)
            foreach ($r in @($Rows)) { $script:AllRulesRows.Add($r) }
            [PSCustomObject]@{ MatchedLogs = $script:MatchedLogs }
        }
    }

    Context 'simple single-row records' {

        It 'passes every cached record to the rules engine' {
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1', 'rec-2') }
            @($script:RulesRows).Count | Should -Be 2
            ($script:RulesRows.id | Sort-Object) | Should -Be @('rec-1', 'rec-2')
        }

        It 'deserialises the cached JSON before handing it over' {
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1') }
            @($script:RulesRows)[0].id | Should -Be 'rec-1'
        }

        It 'returns true on success' {
            Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1', 'rec-2') } | Should -BeTrue
        }

        It 'marks the ledger window Processed once the search is drained' {
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1', 'rec-2') }
            $processed = $script:LedgerWrites | Where-Object { $_.State -eq 'Processed' -and $_.RowKey -eq 'window-1' }
            $processed | Should -Not -BeNullOrEmpty
            $processed.MatchedCount | Should -Be 2
        }

        It 'leaves the window alone while cache rows for the search remain' {
            $script:RemainingAfterProcess = @([PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'rec-9' })
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1') }
            ($script:LedgerWrites | Where-Object { $_.RowKey -eq 'window-1' }) | Should -BeNullOrEmpty
        }
    }

    Context 'no rows found for the batch' {
        BeforeEach { $script:CacheRows = @() }

        It 'returns false without invoking the rules engine' {
            Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('gone-1') } | Should -BeFalse
            Should -Invoke Test-CIPPAuditLogRules -Times 0
        }
    }

    Context 'a record split across multiple rows' {
        BeforeEach {
            # One logical record stored across three physical rows.
            $script:CacheRows = @(
                [PSCustomObject]@{ RowKey = 'rec-1'; OriginalEntityId = $null; SearchId = 'search-1'; JSON = '{"id":"rec-1"}' }
                [PSCustomObject]@{ RowKey = 'big'; OriginalEntityId = 'big'; SearchId = 'search-1'; JSON = '{"id":"big","pad":"AAA' }
                [PSCustomObject]@{ RowKey = 'big-part1'; OriginalEntityId = 'big'; SearchId = 'search-1'; JSON = 'BBB' }
                [PSCustomObject]@{ RowKey = 'big-part2'; OriginalEntityId = 'big'; SearchId = 'search-1'; JSON = 'CCC"}' }
            )
        }

        It 'reassembles the split record into valid JSON' {
            # Fetching one RowKey at a time leaves the reassembler with a fragment.
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1', 'big', 'big-part1', 'big-part2') }
            $big = @($script:RulesRows) | Where-Object { $_.id -eq 'big' }
            $big | Should -Not -BeNullOrEmpty
            $big.pad | Should -Be 'AAABBBCCC'
        }

        It 'yields the split record exactly once, not once per physical row' {
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1', 'big', 'big-part1', 'big-part2') }
            @($script:RulesRows).Count | Should -Be 2
            @($script:RulesRows | Where-Object { $_.id -eq 'big' }).Count | Should -Be 1
        }
    }

    Context 'a batch larger than one chunk' {
        BeforeEach {
            # 250 rows against a chunk size of 100 forces three passes. Smaller fixtures only
            # execute the loop body once, hiding any off-by-one in the slice arithmetic.
            $script:CacheRows = @(
                1..250 | ForEach-Object {
                    [PSCustomObject]@{
                        RowKey           = ('rec-{0:D3}' -f $_)
                        OriginalEntityId = $null
                        SearchId         = 'search-1'
                        JSON             = ('{{"id":"rec-{0:D3}"}}' -f $_)
                    }
                }
            )
        }

        It 'processes every row across all chunks exactly once' {
            $ids = @(1..250 | ForEach-Object { 'rec-{0:D3}' -f $_ })
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = $ids }
            @($script:AllRulesRows).Count | Should -Be 250
            (@($script:AllRulesRows).id | Sort-Object -Unique).Count | Should -Be 250
        }

        It 'invokes the rules engine once per chunk, not once per batch' {
            $ids = @(1..250 | ForEach-Object { 'rec-{0:D3}' -f $_ })
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = $ids }
            # 250 / 100 = 3 calls. This is what bounds peak memory - the whole batch is
            # never resident at once.
            Should -Invoke Test-CIPPAuditLogRules -Times 3 -Exactly
        }

        It 'never builds a filter long enough to trip the request size limit' {
            # Azure rejects ~27kb of filter with HTTP 414 and Azurite ~13kb with HTTP 431,
            # and the outer catch swallows both. Stay well inside the stricter one.
            $ids = @(1..250 | ForEach-Object { 'rec-{0:D3}' -f $_ })
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = $ids }
            $worst = ($script:SeenFilters | Measure-Object -Property Length -Maximum).Maximum
            $worst | Should -BeLessThan 11000
        }
    }

    Context 'orphaned Downloaded windows' {
        BeforeEach {
            $script:DownloadedSweepRows = @(
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'orphan-1'; SearchId = 'search-orphan'; State = 'Downloaded' }
            )
        }

        It 'sweeps a Downloaded window whose search has no cache rows left' {
            $null = Push-AuditLogTenantProcessV2 -Item @{ TenantFilter = 'contoso.com'; RowIds = @('rec-1') }
            $swept = $script:LedgerWrites | Where-Object { $_.RowKey -eq 'orphan-1' }
            $swept | Should -Not -BeNullOrEmpty
            $swept.State | Should -Be 'Processed'
            $swept.MatchedCount | Should -Be 0
        }
    }
}
