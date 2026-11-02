# Realtime grants decide who may see a job's live progress, so they must go to the caller of the request that
# started the job and nobody else. The real bridge lives in Craft; a stand-in type records what CIPPCore asks of it.

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
    $script:ModulesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
    Import-Module (Join-Path $script:ModulesRoot 'CIPPCore/CIPPCore.psd1') -Force 3>$null
    $script:Core = Get-Module CIPPCore

    # What New-CippCoreRequest does for a request: reset the slots, then record the caller once access passed.
    function Enter-Request($User) {
        & $script:Core { param($U) Initialize-CippRequestContext; if ($U) { $script:CippRealtimeUser = $U } } $User
    }
    $script:Job = '6f1c2b8e-1d2a-4c1e-9f0a-3b2c1d4e5f60'
}

AfterAll {
    Remove-Module CIPPCore -Force -ErrorAction SilentlyContinue
    Remove-Item Env:CIPPNG -ErrorAction SilentlyContinue
}

Describe 'Realtime grants' {
    BeforeEach {
        [Craft.Services.RealtimeBridge]::Calls.Clear()
        [Craft.Services.RealtimeBridge]::Data.Clear()
        $env:CIPPNG = 'true'
    }

    It 'grants a queue to the caller of the request that started it' {
        Enter-Request 'alice@contoso.com'
        Add-CIPPRealtimeWatch -JobId $script:Job -Run
        [Craft.Services.RealtimeBridge]::Calls | Should -Be @("WatchRun|alice@contoso.com|$($script:Job)")
    }

    It 'never grants a later job to the previous request''s caller' {
        Enter-Request 'alice@contoso.com'
        Enter-Request $null
        Add-CIPPRealtimeWatch -JobId $script:Job
        [Craft.Services.RealtimeBridge]::Calls | Should -BeNullOrEmpty
    }

    It 'leaves the bridge alone outside CIPP-NG' {
        $env:CIPPNG = $null
        Enter-Request 'alice@contoso.com'
        Add-CIPPRealtimeWatch -JobId $script:Job -Run
        Send-CIPPRealtimeEvent -JobId $script:Job
        [Craft.Services.RealtimeBridge]::Calls | Should -BeNullOrEmpty
    }

    It 'signals a job by id from a worker with no caller' {
        Enter-Request $null
        Send-CIPPRealtimeEvent -JobId $script:Job
        [Craft.Services.RealtimeBridge]::Calls | Should -Be @("Notify|$($script:Job)|update")
    }

    It 'pushes a written async deployment row in the shape the progress endpoints return' {
        $Row = @{
            PartitionKey = $script:Job; RowKey = 'pat@contoso.com'; Source = 'Offboarding'; Status = 'running'
            TaskId = 'task-1'; TenantFilter = 'contoso.com'; Logs = ''
            Steps = '[{"Title":"Revoke sessions","Status":"succeeded","Message":"Done"},{"Title":"Disable sign in","Status":"pending","Message":""}]'
        }

        Send-CIPPAsyncDeploymentUpdate -JobId $script:Job -Row $Row

        $Sent = [Craft.Services.RealtimeBridge]::Data[0]
        $Listed = & $script:Core { param($R) ConvertTo-CIPPAsyncDeploymentRow -Row $R } $Row
        ($Sent.PSObject.Properties.Name -join ',') | Should -Be ($Listed.PSObject.Properties.Name -join ',')
        $Sent.Name | Should -Be 'pat@contoso.com'
        $Sent.Steps[0].Status | Should -Be 'succeeded'
        $Sent.Steps.Count | Should -Be 2
        $Sent.LastUpdate | Should -BeOfType [datetime]
    }
}
