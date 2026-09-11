# Pester tests for Get-CIPPInstanceHealthSample
# The self-diagnostics checks are only as good as this reduction: a signature that stops
# matching turns a FAIL into a silent PASS, which is worse than no diagnostics at all. These
# tests pin each log signature to the counter it feeds, and pin the two shapes that must not
# throw - an empty window and a window of ordinary chatter.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPInstanceHealthSample.ps1')
}

Describe 'Get-CIPPInstanceHealthSample' {
    BeforeEach {
        $script:MixedLines = @(
            '2026-09-10T10:00:00.000Z [ERR] Unhandled: System.OutOfMemoryException: Exception of type was thrown.'
            '2026-09-10T10:00:01.000Z [WRN] Container startup attempt 3 of 5'
            '2026-09-10T10:00:02.000Z [WRN] Restart counter = 2'
            '2026-09-10T10:00:03.000Z [WRN] HTTP pool exhausted for Invoke-ListTenants'
            '2026-09-10T10:00:04.000Z [INF] Limiter slot acquired after 1200ms'
            '2026-09-10T10:00:05.000Z [INF] Limiter slot acquired after 300ms'
            '2026-09-10T10:00:06.000Z [INF] stats heap=1834MB threads=42'
            '2026-09-10T10:00:07.000Z [INF] stats heap=902MB threads=40'
            '2026-09-10T10:00:08.000Z [WRN] T+125.4min: StandardsOrchestrator 0 running 12 pending'
            '2026-09-10T10:00:09.000Z [INF] [HTTP] GET Invoke-ListTenants 200 1500ms'
            '2026-09-10T10:00:10.000Z [INF] [HTTP] GET Invoke-ListTenants 200 500ms'
            '2026-09-10T10:00:11.000Z [INF] [HTTP] POST Invoke-ExecStandards 200 900ms'
            '2026-09-10T10:00:12.000Z [INF] [HTTP] GET Invoke-ListUsers 200 100ms'
            '2026-09-10T10:00:13.000Z [INF] [HTTP] GET Invoke-ListDomains 500 50ms'
            '2026-09-10T10:00:14.000Z [ERR] Graph request failed with 503'
            '2026-09-10T10:00:15.000Z [INF] API Access: AppName=Acme RMM, AppId=11111111-1111-1111-1111-111111111111, IP=203.0.113.9'
            '2026-09-10T10:00:16.000Z [INF] API Access: AppName=Acme RMM, AppId=11111111-1111-1111-1111-111111111111, IP=203.0.113.10'
            '2026-09-10T10:00:17.000Z [INF] API Access: AppName=Other PSA, AppId=22222222-2222-2222-2222-222222222222, IP=198.51.100.4'
        )
    }

    Context 'a window containing every signature' {
        It 'counts one request when the access line repeats under the same request id' {
            $Lines = @(
                '2026-09-10T10:00:15.000Z [INF] [API] aaaa1111 PS Invoke-GetVersion: API Access: AppName=Local, AppId=33333333-3333-3333-3333-333333333333, IP=203.0.113.1'
                '2026-09-10T10:00:15.010Z [INF] [API] aaaa1111 PS Invoke-GetVersion: API Access: AppName=Local, AppId=33333333-3333-3333-3333-333333333333, IP=203.0.113.1'
                '2026-09-10T10:00:15.020Z [INF] [API] bbbb2222 PS Invoke-GetVersion: API Access: AppName=Local, AppId=33333333-3333-3333-3333-333333333333, IP=203.0.113.1'
            )
            @((Get-CIPPInstanceHealthSample -Lines $Lines).Clients)[0].Count | Should -Be 2
        }

        It 'counts an access line whose forwarded IP is empty' {
            $Lines = @('2026-09-10T10:00:15.000Z [INF] API Access: AppName=Local, AppId=33333333-3333-3333-3333-333333333333, IP=')
            $Result = Get-CIPPInstanceHealthSample -Lines $Lines
            @($Result.Clients).Count | Should -Be 1
            @($Result.Clients)[0].Count | Should -Be 1
        }

        It 'counts out-of-memory exceptions' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).OomCount | Should -Be 1
        }

        It 'counts both watchdog restart signatures' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).WatchdogCount | Should -Be 2
        }

        It 'counts pool exhaustion' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).PoolExhaustedCount | Should -Be 1
        }

        It 'counts error-level lines' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).ErrCount | Should -Be 2
        }

        It 'keeps the worst limiter wait, not the last' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).MaxLimiterWaitMs | Should -Be 1200
        }

        It 'keeps the peak heap sample, not the last' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).HeapMb | Should -Be 1834
        }

        It 'counts stalled runs' {
            (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).StalledRunCount | Should -Be 1
        }

        It 'sums endpoint time per function and keeps only the top three' {
            $Top = (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).TopEndpointsMs
            $Top.Count | Should -Be 3
            $Top['Invoke-ListTenants'] | Should -Be 2000
            $Top['Invoke-ExecStandards'] | Should -Be 900
            $Top['Invoke-ListUsers'] | Should -Be 100
            $Top.ContainsKey('Invoke-ListDomains') | Should -BeFalse
        }

        It 'counts egress rejections and captures distinct client names' {
            $Lines = @(
                '2026-09-10T10:00:00.000Z [WRN] Egress cap reached — 429 for AcmeRMM on GET /api/ListTenants; served 1000000000/1000000000 bytes today, Retry-After 30s'
                '2026-09-10T10:00:01.000Z [WRN] Egress cap reached — 429 for AcmeRMM on GET /api/ListUsers; served 1000000000/1000000000 bytes today, Retry-After 30s'
                '2026-09-10T10:00:02.000Z [WRN] Egress cap reached — 429 for OtherPSA on GET /api/ListDomains; served 1000000000/1000000000 bytes today, Retry-After 30s'
            )
            $Sample = Get-CIPPInstanceHealthSample -Lines $Lines
            $Sample.EgressRejectCount | Should -Be 3
            @($Sample.EgressRejectClients) | Should -Be @('AcmeRMM', 'OtherPSA')
        }

        It 'groups API access by AppId and counts repeats' {
            $Clients = (Get-CIPPInstanceHealthSample -Lines $script:MixedLines).Clients
            $Clients.Count | Should -Be 2
            $Acme = $Clients | Where-Object { $_.AppName -eq 'Acme RMM' }
            $Acme.Count | Should -Be 2
            $Acme.AppId | Should -Be '11111111-1111-1111-1111-111111111111'
            $Acme.IP | Should -Be '203.0.113.10'
        }
    }

    Context 'a window with nothing to report' {
        It 'returns zeroed counters for an empty window' {
            $Sample = Get-CIPPInstanceHealthSample -Lines @()
            $Sample.OomCount | Should -Be 0
            $Sample.WatchdogCount | Should -Be 0
            $Sample.PoolExhaustedCount | Should -Be 0
            $Sample.ErrCount | Should -Be 0
            $Sample.MaxLimiterWaitMs | Should -Be 0
            $Sample.StalledRunCount | Should -Be 0
            $Sample.TopEndpointsMs.Count | Should -Be 0
            $Sample.Clients.Count | Should -Be 0
            $Sample.EgressRejectCount | Should -Be 0
            @($Sample.EgressRejectClients).Count | Should -Be 0
        }

        It 'reports no heap reading rather than zero when no sample was logged' {
            (Get-CIPPInstanceHealthSample -Lines @()).HeapMb | Should -BeNullOrEmpty
        }

        It 'ignores ordinary log chatter that matches nothing' {
            $Sample = Get-CIPPInstanceHealthSample -Lines @(
                '2026-09-10T10:00:00.000Z [INF] Tenant cache refreshed for 214 tenants'
                '2026-09-10T10:00:01.000Z [DBG] Token cache hit'
                ''
                '   '
                'a line with no timestamp at all'
            )
            $Sample.OomCount | Should -Be 0
            $Sample.ErrCount | Should -Be 0
            $Sample.HeapMb | Should -BeNullOrEmpty
            $Sample.Clients.Count | Should -Be 0
            $Sample.TopEndpointsMs.Count | Should -Be 0
        }

        It 'does not count a completed run as stalled' {
            # 0 pending is the healthy shape and must stay below the signature.
            $Sample = Get-CIPPInstanceHealthSample -Lines @('2026-09-10T10:00:00.000Z [INF] T+125.4min: StandardsOrchestrator 0 running 0 pending')
            $Sample.StalledRunCount | Should -Be 0
        }
    }
}
