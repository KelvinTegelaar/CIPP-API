# Pester tests for Push-AuditLogProcessingBatchV2 - the audit log V2 batch builder.
#
# Pins the claim semantics, which now operate at SEARCH granularity. The builder claims
# AuditLogCoverage rows, not CacheWebhooks rows: the old per-record claim read the tenant's entire
# cache partition and wrote once per record, which on a 50k-record tenant cost minutes of
# bookkeeping before a single record was examined. One write per search does the same job.
#
# The stamp must still UPDATE, never upsert. An upsert on a row that ledger retention removed
# mid-loop recreates it as a stateless shell that re-enters every cycle forever.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogProcessingBatchV2.ps1'

    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Update-CIPPAzDataTableEntity { param($Context, $Entity, $OperationType, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, $OperationType) }
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) }

    . $FunctionPath
}

Describe 'Push-AuditLogProcessingBatchV2' {

    BeforeEach {
        $script:Stamped = [System.Collections.Generic.List[string]]::new()
        $script:VanishedRowKey = $null
        $script:CacheReadFilters = [System.Collections.Generic.List[string]]::new()

        $script:LedgerRows = @(
            [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'window-1'; SearchId = 'search-1'; State = 'Downloaded'; RecordCount = 10; Timestamp = [DateTimeOffset]::UtcNow }
            [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'window-2'; SearchId = 'search-2'; State = 'Downloaded'; RecordCount = 20; Timestamp = [DateTimeOffset]::UtcNow }
        )
        # Legacy pre-partitioning rows; empty on any instance that has cycled once.
        $script:LegacyCacheRows = @()

        Mock -CommandName Get-CippTable -MockWith { param($TableName) @{ Context = "ctx:$TableName" } }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter, $Property)
            if ($Context -like '*AuditLogCoverage*') { return $script:LedgerRows }
            $script:CacheReadFilters.Add([string]$Filter)
            return $script:LegacyCacheRows
        }

        # Mirrors the table service: an update on a row that no longer exists fails.
        Mock -CommandName Update-CIPPAzDataTableEntity -MockWith {
            param($Context, $Entity, $OperationType, [switch]$Force)
            foreach ($Stamp in @($Entity)) {
                if ($script:VanishedRowKey -and $Stamp.RowKey -eq $script:VanishedRowKey) {
                    throw 'The specified resource does not exist.'
                }
                $script:Stamped.Add([string]$Stamp.RowKey)
            }
        }

        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            throw 'Add-CIPPAzDataTableEntity must not be used for claim stamps - an upsert resurrects deleted rows'
        }

        Mock -CommandName New-CippQueueEntry -MockWith { [PSCustomObject]@{ RowKey = 'queue-1' } }
    }

    Context 'claim granularity' {

        It 'claims the ledger, never the individual cache records' {
            # The change this file exists to protect: one write per search, not per record.
            $null = Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }
            ($script:Stamped | Sort-Object) | Should -Be @('window-1', 'window-2')
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        }

        It 'writes once per search regardless of how many records it holds' {
            $script:LedgerRows = @(
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'window-1'; SearchId = 'search-1'; State = 'Downloaded'; RecordCount = 50000; Timestamp = [DateTimeOffset]::UtcNow }
            )
            $null = Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }
            Should -Invoke Update-CIPPAzDataTableEntity -Times 1 -Exactly
        }

        It 'marks claimed searches as Processing' {
            $null = Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }
            Should -Invoke Update-CIPPAzDataTableEntity -Times 2 -Exactly -ParameterFilter {
                $Entity.State -eq 'Processing'
            }
        }

        It 'skips freshly claimed searches and reclaims stale ones' {
            $script:LedgerRows = @(
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'fresh'; SearchId = 's-fresh'; State = 'Processing'; RecordCount = 1; Timestamp = [DateTimeOffset]::UtcNow }
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'stale'; SearchId = 's-stale'; State = 'Processing'; RecordCount = 1; Timestamp = [DateTimeOffset]::UtcNow.AddHours(-3) }
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'ready'; SearchId = 's-ready'; State = 'Downloaded'; RecordCount = 1; Timestamp = [DateTimeOffset]::UtcNow }
            )
            $Batches = @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' })
            ($Batches.WindowRowKey | Sort-Object) | Should -Be @('ready', 'stale')
            $script:Stamped | Should -Not -Contain 'fresh'
        }

        It 'ignores states that are not ready for processing' {
            $script:LedgerRows = @(
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'planned'; SearchId = 's1'; State = 'Planned'; RecordCount = 0; Timestamp = [DateTimeOffset]::UtcNow }
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'created'; SearchId = 's2'; State = 'Created'; RecordCount = 0; Timestamp = [DateTimeOffset]::UtcNow }
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'done'; SearchId = 's3'; State = 'Processed'; RecordCount = 5; Timestamp = [DateTimeOffset]::UtcNow }
            )
            @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }).Count | Should -Be 0
            Should -Invoke Update-CIPPAzDataTableEntity -Times 0
        }

        It 'skips a window with no SearchId rather than emitting an unusable batch item' {
            $script:LedgerRows = @(
                [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'no-search'; SearchId = $null; State = 'Downloaded'; RecordCount = 0; Timestamp = [DateTimeOffset]::UtcNow }
            )
            @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }).Count | Should -Be 0
        }

        It 'keeps claiming when one window vanishes mid-loop' {
            $script:VanishedRowKey = 'window-1'
            $Batches = @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' })
            # The vanished row fails quietly and is not batched; the survivor still is.
            $Batches.WindowRowKey | Should -Be @('window-2')
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        }
    }

    Context 'batch construction' {

        It 'emits one batch item per search, carrying the ids the activity needs' {
            $Batches = @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' })
            @($Batches).Count | Should -Be 2
            ($Batches.SearchId | Sort-Object) | Should -Be @('search-1', 'search-2')
            $Batches.FunctionName | Should -Be @('AuditLogTenantProcessV2', 'AuditLogTenantProcessV2')
            $Batches.QueueId | Should -Be @('queue-1', 'queue-1')
        }

        It 'resolves the tenant from Parameters when nested' {
            $Batches = @(Push-AuditLogProcessingBatchV2 -Item ([PSCustomObject]@{ Parameters = @{ TenantFilter = 'contoso.com' } }))
            @($Batches).Count | Should -Be 2
            $Batches[0].TenantFilter | Should -Be 'contoso.com'
        }

        It 'returns nothing when no searches are claimable' {
            $script:LedgerRows = @()
            @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }).Count | Should -Be 0
            Should -Invoke Update-CIPPAzDataTableEntity -Times 0
        }
    }

    Context 'legacy rows written before per-search partitioning' {

        It 'batches leftover rows from the old tenant partition' {
            $script:LedgerRows = @()
            $script:LegacyCacheRows = @(
                1..750 | ForEach-Object { [PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = ('old-{0:D3}' -f $_) } }
            )
            $Batches = @(Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' })
            @($Batches).Count | Should -Be 2
            @($Batches[0].LegacyRowIds).Count | Should -Be 500
            @($Batches[1].LegacyRowIds).Count | Should -Be 250
        }

        It 'reads the legacy partition by key only, never pulling JSON payloads' {
            $script:LegacyCacheRows = @([PSCustomObject]@{ PartitionKey = 'contoso.com'; RowKey = 'old-1' })
            $null = Push-AuditLogProcessingBatchV2 -Item @{ TenantFilter = 'contoso.com' }
            $script:CacheReadFilters | Should -Contain "PartitionKey eq 'contoso.com'"
        }
    }
}
