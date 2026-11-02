# Pester tests for Invoke-ListInstanceDiagnostics (Timeline action)
# InstanceHealth rows now share one PartitionKey with the bucket in RowKey/Bucket and the row
# type in Kind, so the endpoint splits rows by Kind instead of parsing RowKey. This pins that
# a mocked mixed-Kind row set still groups clients under the right bucket and emits a boot event.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ListInstanceDiagnostics.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) @{ Context = 'stub' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-LogMessage { param($API, $message, $sev, $LogData) }
    function Get-CippApiClient { param($AppId) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPEgressAccounting.ps1')

    function New-DiagRequest {
        param([string]$Action = 'Timeline', [int]$Hours = 24)
        [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ListInstanceDiagnostics' }
            Query  = [pscustomobject]@{ Action = $Action; Hours = $Hours }
        }
    }

    $script:HealthRows = @(
        [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:00_sample'; Bucket = '2026-09-10T10:00'; Kind = 'sample'; OomCount = 0; WatchdogCount = 0; PoolExhaustedCount = 0; ErrCount = 0; MaxLimiterWaitMs = 0; StalledRunCount = 0; HeapMb = 500; HeapMbLive = $null; GcHeapLimitMb = 3072; TopEndpointsMs = $null }
        [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:00_client_11111111-1111-1111-1111-111111111111'; Bucket = '2026-09-10T10:00'; Kind = 'client'; AppId = '11111111-1111-1111-1111-111111111111'; AppName = 'Acme RMM'; IP = '203.0.113.9'; Count = 5 }
        [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:05_boot'; Bucket = '2026-09-10T10:05'; Kind = 'boot'; BootTime = '2026-09-10T10:05:00Z'; GapMinutes = 3 }
    )

    $script:AppA = '11111111-1111-1111-1111-111111111111'
    $script:AppB = '22222222-2222-2222-2222-222222222222'

    # Craft's egress table: 15 minute bucket rows per API client plus an instance-total
    # partition, and the same split for today's daily rollup.
    $script:EgressBucketRows = @(
        [pscustomobject]@{ PartitionKey = $script:AppA; RowKey = 'bkt_20260910T100000Z'; Bytes = 700000; Requests = 7; Shed = 2; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-10T10:00:00Z'); AppId = $script:AppA }
        [pscustomobject]@{ PartitionKey = $script:AppB; RowKey = 'bkt_20260910T100000Z'; Bytes = 200000; Requests = 2; Shed = 1; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-10T10:00:00Z'); AppId = $script:AppB }
        [pscustomobject]@{ PartitionKey = 'instance-total'; RowKey = 'bkt_20260910T100000Z'; Bytes = 900000; Requests = 9; Shed = 3; CapBytes = 1000000; BucketStartUtc = [DateTimeOffset]::Parse('2026-09-10T10:00:00Z') }
    )
    $script:EgressDayRows = @(
        [pscustomobject]@{ PartitionKey = $script:AppA; RowKey = 'day_20260910'; Bytes = 700000; Requests = 7; Shed = 2; CapBytes = 1000000; DateUtc = '2026-09-10' }
        [pscustomobject]@{ PartitionKey = $script:AppB; RowKey = 'day_20260910'; Bytes = 200000; Requests = 2; Shed = 1; CapBytes = 1000000; DateUtc = '2026-09-10' }
        [pscustomobject]@{ PartitionKey = 'instance-total'; RowKey = 'day_20260910'; Bytes = 900000; Requests = 9; Shed = 3; CapBytes = 1000000; DateUtc = '2026-09-10'; Enforcing = $true; CapReachedUtc = [DateTimeOffset]::Parse('2026-09-10T10:07:00Z') }
    )
}

Describe 'Invoke-ListInstanceDiagnostics egress and row splitting' {
    BeforeEach {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:HealthRows } -ParameterFilter { $Filter -match "PartitionKey eq 'InstanceHealth'" }
        Mock -CommandName Get-CippApiClient -MockWith {
            @(
                [pscustomobject]@{ ClientId = $script:AppA; AppName = 'Acme RMM' }
                [pscustomobject]@{ ClientId = $script:AppB; AppName = 'Other PSA' }
            )
        }
    }

    Context 'with egress accounting rows in the table' {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:EgressBucketRows } -ParameterFilter { $Filter -like 'RowKey ge*' }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:EgressDayRows } -ParameterFilter { $Filter -like "RowKey eq 'day_*" }
        }

        It 'groups clients under their sample bucket and emits a boot event from mixed Kind rows' {
            $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Timeline') -TriggerMetadata $null

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results.Buckets | Should -HaveCount 1
            $Response.Body.Results.Buckets[0].Bucket | Should -Be '2026-09-10T10:00'
            $Response.Body.Results.Buckets[0].Clients | Should -HaveCount 1
            $Response.Body.Results.Buckets[0].Clients[0].AppId | Should -Be $script:AppA
            $Response.Body.Results.Buckets[0].Clients[0].Count | Should -Be 5

            $Response.Body.Results.HeapCapMb | Should -Be 3072

            $Response.Body.Results.Events | Should -HaveCount 1
            $Response.Body.Results.Events[0].Type | Should -Be 'boot'
            $Response.Body.Results.Events[0].Bucket | Should -Be '2026-09-10T10:05'
            $Response.Body.Results.Events[0].GapMinutes | Should -Be 3
        }

        It 'returns the egress accounting block with bucket totals and resolved client names' {
            $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Timeline') -TriggerMetadata $null
            $Egress = $Response.Body.Results.Egress

            $Egress.Available | Should -BeTrue
            $Egress.BucketMinutes | Should -Be 15
            $Egress.Buckets | Should -HaveCount 1
            $Egress.Buckets[0].BucketStart | Should -Be '2026-09-10T10:00:00Z'
            $Egress.Buckets[0].Bytes | Should -Be 900000
            $Egress.Buckets[0].Requests | Should -Be 9
            $Egress.Buckets[0].Clients | Should -HaveCount 2
            ($Egress.Buckets[0].Clients | Where-Object { $_.AppId -eq $script:AppB }).AppName | Should -Be 'Other PSA'

            $Egress.TodayBytes | Should -Be 900000
            $Egress.TodayShed | Should -Be 3
            $Egress.Enforcing | Should -BeTrue
            $Egress.Clients[0].AppName | Should -Be 'Acme RMM'
        }

        It 'fails the egress check and names the busiest client when the cap was reached' {
            $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Checks') -TriggerMetadata $null
            $Check = $Response.Body.Results | Where-Object { $_.Check -eq 'egress' }

            $Check.Status | Should -Be 'FAIL'
            $Check.Detail | Should -BeLike '*cap reached at 2026-09-10T10:07:00Z*'
            $Check.Detail | Should -BeLike '*3 request(s) refused with 429*'
            $Check.Detail | Should -BeLike '*busiest: Acme RMM*'
            $Check.Fix | Should -Not -BeNullOrEmpty
        }
    }

    Context 'with no egress accounting rows' {
        It 'reports egress unavailable on the timeline' {
            $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Timeline') -TriggerMetadata $null
            $Response.Body.Results.Egress.Available | Should -BeFalse
        }

        It 'reports the egress check as INFO' {
            $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Checks') -TriggerMetadata $null
            $Check = $Response.Body.Results | Where-Object { $_.Check -eq 'egress' }
            $Check.Status | Should -Be 'INFO'
            $Check.Detail | Should -BeLike 'No API egress recorded today*'
        }
    }
}
