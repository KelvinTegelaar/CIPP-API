# Pester tests for Get-CIPPEgressAccounting
# Craft owns the accounting table, so "table absent or empty" must stay indistinguishable from a
# quiet day: both return $null rather than a fake zero reading.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{ Context = 'stub' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CippApiClient { param($AppId) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPEgressAccounting.ps1')

    $script:Now = [DateTime]::Parse('2026-09-12T10:20:00Z').ToUniversalTime()
    $script:AppA = '11111111-1111-1111-1111-111111111111'
    $script:AppB = '22222222-2222-2222-2222-222222222222'

    $script:BucketRows = @(
        [pscustomobject]@{ PartitionKey = $script:AppA; RowKey = 'bkt_20260912T100000Z'; Bytes = 600; Requests = 6; Shed = 0; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-12T10:00:00Z'); AppId = $script:AppA }
        [pscustomobject]@{ PartitionKey = $script:AppB; RowKey = 'bkt_20260912T100000Z'; Bytes = 300; Requests = 3; Shed = 1; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-12T10:00:00Z'); AppId = $script:AppB }
        [pscustomobject]@{ PartitionKey = 'instance-total'; RowKey = 'bkt_20260912T100000Z'; Bytes = 1000; Requests = 10; Shed = 1; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-12T10:00:00Z') }
        [pscustomobject]@{ PartitionKey = $script:AppA; RowKey = 'bkt_20260912T101500Z'; Bytes = 250; Requests = 2; Shed = 0; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-12T10:15:00Z'); AppId = $script:AppA }
    )

    $script:DayRows = @(
        [pscustomobject]@{ PartitionKey = $script:AppA; RowKey = 'day_20260912'; Bytes = 850; Requests = 8; Shed = 0; CapBytes = 1000000; DateUtc = '2026-09-12' }
        [pscustomobject]@{ PartitionKey = $script:AppB; RowKey = 'day_20260912'; Bytes = 400; Requests = 4; Shed = 1; CapBytes = 1000000; DateUtc = '2026-09-12' }
        [pscustomobject]@{ PartitionKey = 'instance-total'; RowKey = 'day_20260912'; Bytes = 1250; Requests = 12; Shed = 1; CapBytes = 1000000; DateUtc = '2026-09-12'; Enforcing = $true; CapReachedUtc = [DateTimeOffset]::Parse('2026-09-12T10:05:00Z') }
    )
}

Describe 'Get-CIPPEgressAccounting' {
    BeforeEach {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:BucketRows } -ParameterFilter { $Filter -like 'RowKey ge*' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:DayRows } -ParameterFilter { $Filter -like "RowKey eq 'day_*" }
        Mock -CommandName Get-CippApiClient -MockWith {
            @(
                [pscustomobject]@{ ClientId = $script:AppA; AppName = 'Acme RMM' }
                [pscustomobject]@{ ClientId = $script:AppB; AppName = 'Other PSA' }
            )
        }
    }

    It 'aggregates buckets and resolves client names' {
        $Result = Get-CIPPEgressAccounting -Hours 6 -Now $script:Now

        $Result.BucketMinutes | Should -Be 15
        $Result.Buckets | Should -HaveCount 2
        $Result.Buckets[0].BucketStart | Should -Be '2026-09-12T10:00:00Z'
        $Result.Buckets[0].Bytes | Should -Be 1000
        $Result.Buckets[0].Requests | Should -Be 10
        $Result.Buckets[0].Clients | Should -HaveCount 2
        ($Result.Buckets[0].Clients | Where-Object { $_.AppId -eq $script:AppB }).Bytes | Should -Be 300
        ($Result.Buckets[0].Clients | Where-Object { $_.AppId -eq $script:AppA }).AppName | Should -Be 'Acme RMM'
        ($Result.Buckets[0].Clients | Where-Object { $_.AppId -eq $script:AppA }).Bytes | Should -Be 600
    }

    It 'falls back to the sum of clients when the bucket has no instance-total row' {
        # Second bucket only has the one client row.
        $Result = Get-CIPPEgressAccounting -Hours 6 -Now $script:Now
        $Result.Buckets[1].BucketStart | Should -Be '2026-09-12T10:15:00Z'
        $Result.Buckets[1].Bytes | Should -Be 250
        $Result.Buckets[1].Requests | Should -Be 2
    }

    It 'reads the daily totals from the instance-total row and sorts clients by bytes' {
        $Result = Get-CIPPEgressAccounting -Hours 6 -Now $script:Now

        $Result.TodayBytes | Should -Be 1250
        $Result.TodayRequests | Should -Be 12
        $Result.TodayShed | Should -Be 1
        $Result.CapBytes | Should -Be 1000000
        $Result.Enforcing | Should -BeTrue
        $Result.CapReachedUtc | Should -Be '2026-09-12T10:05:00Z'
        $Result.Clients | Should -HaveCount 2
        $Result.Clients[0].AppName | Should -Be 'Acme RMM'
        $Result.Clients[0].Bytes | Should -Be 850
    }

    It 'returns null when the table has no rows' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() } -ParameterFilter { $Filter -like 'RowKey ge*' }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @() } -ParameterFilter { $Filter -like "RowKey eq 'day_*" }
        Get-CIPPEgressAccounting -Hours 6 -Now $script:Now | Should -BeNullOrEmpty
    }

    It 'returns null when the table cannot be read' {
        Mock -CommandName Get-CIPPTable -MockWith { throw 'TableNotFound' }
        Get-CIPPEgressAccounting -Hours 6 -Now $script:Now | Should -BeNullOrEmpty
    }

    It 'falls back to the AppId when no API client record matches' {
        Mock -CommandName Get-CippApiClient -MockWith { @() }
        $Result = Get-CIPPEgressAccounting -Hours 6 -Now $script:Now
        $Result.Clients[0].AppName | Should -Be $script:AppA
    }
}
