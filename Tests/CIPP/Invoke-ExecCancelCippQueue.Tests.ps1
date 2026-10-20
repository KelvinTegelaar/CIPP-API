# Cancelling a queue stops work other users may be waiting on, so only the user who started it may cancel it.
# The bridges live in Craft; stand-in types record what the endpoint asks of them.

BeforeAll {
    if (-not ('Craft.Services.WorkerMetricsBridge' -as [type])) {
        Add-Type -TypeDefinition @'
namespace Craft.Services {
    public static class QueueStatusBridge {
        public static string Runs = "[]";
        public static string GetRuns(string lookup) { return Runs; }
        public static void RegisterQueueMetadata(string queueId, string label, string link, string reference) { }
    }
    public static class WorkerMetricsBridge {
        public static readonly System.Collections.Generic.List<string> Cancelled = new System.Collections.Generic.List<string>();
        public static int CancelRun(string runName) { Cancelled.Add(runName); return 5; }
    }
}
'@
    }
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CippTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }
    function Add-CIPPRealtimeWatch { param($JobId, [switch]$Run) }
    function Add-CIPPAzDataTableEntity { param($Entity) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/CippQueue/New-CippQueueEntry.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecCancelCippQueue.ps1')

    $script:QueueId = '6f1c2b8e-1d2a-4c1e-9f0a-3b2c1d4e5f60'
    function New-CancelRequest($User) {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCancelCippQueue' }
            Headers = @{ 'x-ms-client-principal-name' = $User }
            Body    = [pscustomobject]@{ QueueId = $script:QueueId }
        }
    }
}

AfterAll {
    Remove-Item Env:CIPPNG -ErrorAction SilentlyContinue
}

Describe 'Invoke-ExecCancelCippQueue' {
    BeforeEach {
        $env:CIPPNG = 'true'
        [Craft.Services.WorkerMetricsBridge]::Cancelled.Clear()
        [Craft.Services.QueueStatusBridge]::Runs = "[{`"runName`":`"GraphRequestOrchestrator-$($script:QueueId)`"}]"
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match $script:QueueId) { [pscustomobject]@{ RowKey = $script:QueueId; Owner = 'alice@contoso.com'; Name = 'Users (All Tenants)' } }
        }
    }

    It 'cancels the runs of a queue the caller started' {
        $Response = Invoke-ExecCancelCippQueue -Request (New-CancelRequest 'Alice@contoso.com')

        $Response.StatusCode | Should -Be 200
        [Craft.Services.WorkerMetricsBridge]::Cancelled | Should -Be @("GraphRequestOrchestrator-$($script:QueueId)")
    }

    It 'refuses a queue someone else started' {
        $Response = Invoke-ExecCancelCippQueue -Request (New-CancelRequest 'bob@contoso.com')

        $Response.StatusCode | Should -Be 403
        [Craft.Services.WorkerMetricsBridge]::Cancelled | Should -BeNullOrEmpty
    }

    It 'refuses a queue with no recorded owner' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = $script:QueueId; Name = 'Timer run' } }

        $Response = Invoke-ExecCancelCippQueue -Request (New-CancelRequest 'alice@contoso.com')

        $Response.StatusCode | Should -Be 403
        [Craft.Services.WorkerMetricsBridge]::Cancelled | Should -BeNullOrEmpty
    }

    It 'returns 404 for an unknown queue' {
        Mock Get-CIPPAzDataTableEntity { }

        (Invoke-ExecCancelCippQueue -Request (New-CancelRequest 'alice@contoso.com')).StatusCode | Should -Be 404
    }
}

Describe 'New-CippQueueEntry owner' {
    BeforeEach {
        $env:CIPPNG = 'true'
        Mock Add-CIPPAzDataTableEntity { }
    }

    It 'records the caller of the request as the owner' {
        $script:CippRealtimeUser = 'alice@contoso.com'

        $Entry = New-CippQueueEntry -Name 'Users (All Tenants)' -Reference 'AllTenants-users'

        $Entry.Owner | Should -Be 'alice@contoso.com'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.Owner -eq 'alice@contoso.com' -and $Entity.RowKey -eq $Entry.RowKey }
    }

    It 'leaves a queue started outside a request without an owner, so nobody can cancel it' {
        $script:CippRealtimeUser = $null

        $Entry = New-CippQueueEntry -Name 'Timer run'

        $Entry.Owner | Should -BeNullOrEmpty
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
