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

    . $FunctionPath

    function New-DiagRequest {
        param([string]$Action = 'Timeline', [int]$Hours = 24)
        [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ListInstanceDiagnostics' }
            Query  = [pscustomobject]@{ Action = $Action; Hours = $Hours }
        }
    }
}

Describe 'Invoke-ListInstanceDiagnostics Timeline row splitting' {
    It 'groups clients under their sample bucket and emits a boot event from mixed Kind rows' {
        $Rows = @(
            [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:00_sample'; Bucket = '2026-09-10T10:00'; Kind = 'sample'; OomCount = 0; WatchdogCount = 0; PoolExhaustedCount = 0; ErrCount = 0; MaxLimiterWaitMs = 0; StalledRunCount = 0; HeapMb = 500; HeapMbLive = $null; GcHeapLimitMb = 3072; TopEndpointsMs = $null; EgressBytesToday = 1048576; EgressBytes = 204800; EgressCapBytes = 10485760 }
            [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:00_client_11111111-1111-1111-1111-111111111111'; Bucket = '2026-09-10T10:00'; Kind = 'client'; AppId = '11111111-1111-1111-1111-111111111111'; AppName = 'Acme RMM'; IP = '203.0.113.9'; Count = 5 }
            [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:05_boot'; Bucket = '2026-09-10T10:05'; Kind = 'boot'; BootTime = '2026-09-10T10:05:00Z'; GapMinutes = 3 }
        )

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $Rows } -ParameterFilter { $Filter -match "PartitionKey eq 'InstanceHealth'" }

        $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Timeline') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.Buckets | Should -HaveCount 1
        $Response.Body.Results.Buckets[0].Bucket | Should -Be '2026-09-10T10:00'
        $Response.Body.Results.Buckets[0].Clients | Should -HaveCount 1
        $Response.Body.Results.Buckets[0].Clients[0].AppId | Should -Be '11111111-1111-1111-1111-111111111111'
        $Response.Body.Results.Buckets[0].Clients[0].Count | Should -Be 5

        $Response.Body.Results.Buckets[0].EgressBytesToday | Should -Be 1048576
        $Response.Body.Results.Buckets[0].EgressBytes | Should -Be 204800
        $Response.Body.Results.EgressCapBytes | Should -Be 10485760
        $Response.Body.Results.EgressAvailable | Should -BeTrue

        $Response.Body.Results.HeapCapMb | Should -Be 3072

        $Response.Body.Results.Events | Should -HaveCount 1
        $Response.Body.Results.Events[0].Type | Should -Be 'boot'
        $Response.Body.Results.Events[0].Bucket | Should -Be '2026-09-10T10:05'
        $Response.Body.Results.Events[0].GapMinutes | Should -Be 3
    }

    It 'reports egress unavailable when no sample in the window carries a reading' {
        $Rows = @(
            [pscustomobject]@{ PartitionKey = 'InstanceHealth'; RowKey = '2026-09-10T10:00_sample'; Bucket = '2026-09-10T10:00'; Kind = 'sample'; OomCount = 0; WatchdogCount = 0; PoolExhaustedCount = 0; ErrCount = 0; MaxLimiterWaitMs = 0; StalledRunCount = 0; HeapMb = 500; HeapMbLive = $null; GcHeapLimitMb = 3072; TopEndpointsMs = $null }
        )

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $Rows } -ParameterFilter { $Filter -match "PartitionKey eq 'InstanceHealth'" }

        $Response = Invoke-ListInstanceDiagnostics -Request (New-DiagRequest -Action 'Timeline') -TriggerMetadata $null

        $Response.Body.Results.EgressAvailable | Should -BeFalse
        $Response.Body.Results.Buckets[0].EgressBytes | Should -BeNullOrEmpty
        $Response.Body.Results.Buckets[0].EgressBytesToday | Should -BeNullOrEmpty
        $Response.Body.Results.EgressCapBytes | Should -BeNullOrEmpty
    }
}
