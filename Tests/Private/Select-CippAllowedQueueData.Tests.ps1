# Runs are shared between users, so a tenant-restricted user can be handed the run another user started for every
# tenant. Nothing about a tenant outside their scope may reach them: not a task, a count, a name, nor a live event.

BeforeAll {
    $script:ModulesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
    Import-Module (Join-Path $script:ModulesRoot 'CIPPCore/CIPPCore.psd1') -Force 3>$null
    $script:Core = Get-Module CIPPCore

    # What New-CippCoreRequest does for a request: reset the slots, then apply the caller's scope ($null = unrestricted).
    function Enter-Request($AllowedTenants) {
        & $script:Core { param($A) Initialize-CippRequestContext; $script:CippAllowedTenantsStorage.Value = $A } $AllowedTenants
    }

    $script:Shared = '11111111-1111-1111-1111-111111111111'
    $script:Mine = '22222222-2222-2222-2222-222222222222'
    function New-Queue($QueueId, $Name) {
        [PSCustomObject]@{
            PartitionKey = 'CippQueue'; RowKey = "GraphRequestOrchestrator-$QueueId"; QueueId = $QueueId; Name = $Name
            Link = '/tenant/x?tenantFilter=other.com'; Reference = 'other.com-PKHASH'
            TotalTasks = 3; CompletedTasks = 2; RunningTasks = 1; FailedTasks = 1; PercentComplete = 66.7
            QueuedAhead = 4; RunsAhead = 1; Status = 'Running'; Timestamp = '2026-10-20T00:00:00Z'
            Tasks = @(
                [PSCustomObject]@{ Name = 'mine.com'; Status = 'Completed' }
                [PSCustomObject]@{ Name = 'other.com'; Status = 'Failed' }
                [PSCustomObject]@{ Name = 'mine2.com'; Status = 'Running' }
            )
        }
    }
}

AfterAll {
    Remove-Module CIPPCore -Force -ErrorAction SilentlyContinue
}

Describe 'Select-CippAllowedQueueData' {
    BeforeEach {
        Mock -ModuleName CIPPCore Get-CippTable { @{} }
        Mock -ModuleName CIPPCore Get-CIPPAzDataTableEntity { [PSCustomObject]@{ PartitionKey = 'CippQueue'; RowKey = $script:Mine } }
        Mock -ModuleName CIPPCore Get-Tenants {
            @([PSCustomObject]@{ defaultDomainName = 'mine.com'; customerId = 'c1' }
                [PSCustomObject]@{ defaultDomainName = 'mine2.com'; customerId = 'c2' })
        }
        $script:Queues = @((New-Queue $script:Shared 'Users (133 missing tenants)'), (New-Queue $script:Mine 'Groups Cache Sync (All Tenants)'))
    }

    It 'leaves an unrestricted caller''s view untouched' {
        Enter-Request $null

        $Result = @(Select-CippAllowedQueueData -Queues $script:Queues -User 'alice@contoso.com')

        $Result[0].Tasks.Name | Should -Contain 'other.com'
        $Result[0].Polled | Should -BeNullOrEmpty
        Should -Invoke -ModuleName CIPPCore Get-Tenants -Times 0
    }

    It 'narrows another user''s run to the caller''s tenants and drops what names or counts the rest' {
        Enter-Request @('c1', 'c2')

        $Shared = @(Select-CippAllowedQueueData -Queues $script:Queues -User 'alice@contoso.com')[0]

        $Shared.Tasks.Name | Should -Be @('mine.com', 'mine2.com')
        $Shared.TotalTasks | Should -Be 2
        $Shared.CompletedTasks | Should -Be 1
        $Shared.FailedTasks | Should -Be 0
        $Shared.RunningTasks | Should -Be 1
        $Shared.Name | Should -Be 'Users'
        $Shared.Link | Should -BeNullOrEmpty
        $Shared.Reference | Should -BeNullOrEmpty
        $Shared.RowKey | Should -Be $script:Shared
        $Shared.Polled | Should -BeTrue
        ($Shared | ConvertTo-Json -Depth 5) | Should -Not -Match 'other\.com|133'
    }

    It 'keeps the caller''s own run whole, marked for polling' {
        Enter-Request @('c1', 'c2')

        $Mine = @(Select-CippAllowedQueueData -Queues $script:Queues -User 'alice@contoso.com')[1]

        $Mine.Name | Should -Be 'Groups Cache Sync (All Tenants)'
        $Mine.TotalTasks | Should -Be 3
        $Mine.Polled | Should -BeTrue
    }

    It 'lists only the caller''s own runs when not asked for one by id' {
        Enter-Request @('c1', 'c2')

        $Result = @(Select-CippAllowedQueueData -Queues $script:Queues -User 'alice@contoso.com' -OwnOnly)

        $Result.Count | Should -Be 1
        $Result[0].Name | Should -Be 'Groups Cache Sync (All Tenants)'
    }

    It 'treats a scope that resolved to no tenants as restricted, not unrestricted' {
        Enter-Request @()
        Mock -ModuleName CIPPCore Get-Tenants { }
        Mock -ModuleName CIPPCore Get-CIPPAzDataTableEntity { }

        $Shared = @(Select-CippAllowedQueueData -Queues $script:Queues -User 'alice@contoso.com')[0]

        @($Shared.Tasks).Count | Should -Be 0
        $Shared.TotalTasks | Should -Be 0
    }
}

Describe 'Get-CIPPQueueData live grants' {
    BeforeAll {
        if (-not ('Craft.Services.RealtimeBridge' -as [type])) {
            Add-Type -TypeDefinition @'
namespace Craft.Services {
    public static class RealtimeBridge {
        public static readonly System.Collections.Generic.List<string> Calls = new System.Collections.Generic.List<string>();
        public static void Watch(string userId, string jobId) { Calls.Add("Watch|" + userId + "|" + jobId); }
        public static void WatchRun(string userId, string jobId) { Calls.Add("WatchRun|" + userId + "|" + jobId); }
        public static readonly System.Collections.Generic.List<object> Data = new System.Collections.Generic.List<object>();
        public static void Notify(string jobId, string mode, object data) { Calls.Add("Notify|" + jobId + "|" + mode); Data.Add(data); }
    }
}
'@
        }
    }
    BeforeEach {
        [Craft.Services.RealtimeBridge]::Calls.Clear()
        Mock -ModuleName CIPPCore Get-CippTable { @{} }
        Mock -ModuleName CIPPCore Get-CIPPAzDataTableEntity { }
    }
    AfterEach {
        Remove-Item Env:CIPPNG -ErrorAction SilentlyContinue
    }

    It 'grants a restricted caller no live events, which would carry the unfiltered run' {
        Enter-Request @('c1')
        & $script:Core { $script:CippRealtimeUser = 'alice@contoso.com' }
        $env:CIPPNG = 'true'
        Mock -ModuleName CIPPCore ConvertFrom-Json { }

        try { $null = Get-CIPPQueueData -QueueId $script:Shared } catch { }

        [Craft.Services.RealtimeBridge]::Calls | Should -BeNullOrEmpty
    }

    It 'still grants an unrestricted caller live events' {
        Enter-Request $null
        & $script:Core { $script:CippRealtimeUser = 'alice@contoso.com' }
        $env:CIPPNG = 'true'

        try { $null = Get-CIPPQueueData -QueueId $script:Shared } catch { }

        [Craft.Services.RealtimeBridge]::Calls | Should -Be @("WatchRun|alice@contoso.com|$($script:Shared)")
    }
}
