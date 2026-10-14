BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Orchestrators = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions'
    $Http = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions'
    . (Join-Path $Orchestrators 'Start-CIPPOrchestrator.ps1')
    . (Join-Path $Orchestrators 'Resolve-CIPPOrchestratorPriority.ps1')
    . (Join-Path $Orchestrators 'Start-SchedulerOrchestrator.ps1')
    . (Join-Path $Orchestrators 'Start-UpdatePermissionsOrchestrator.ps1')
    . (Join-Path $Orchestrators 'Start-TenantDynamicGroupOrchestrator.ps1')
    . (Join-Path $Orchestrators 'Start-DomainOrchestrator.ps1')
    . (Join-Path $Orchestrators 'Start-ApplicationOrchestrator.ps1')
    . (Join-Path $Orchestrators 'Start-AuditLogSearchCreationV2.ps1')
    . (Join-Path $Orchestrators 'Start-CIPPDBTestsRun.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Timer Functions/Start-TableCleanup.ps1')
    . (Join-Path $Http 'CIPP/Core/Invoke-ExecCPVRefresh.ps1')
    . (Join-Path $Http 'Tenant/Standards/Invoke-ExecDomainAnalyser.ps1')
    . (Join-Path $Http 'Endpoint/Applications/Invoke-ExecAppUpload.ps1')
    . (Join-Path $Http 'Tenant/Tests/Invoke-ExecTestRun.ps1')

    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Same stand-in for Craft's bridge as Start-CIPPOrchestrator.Craft.Tests.ps1: records each queued run and
    # reports the names in ActiveNames as still running.
    if (-not ('Craft.Services.OrchestratorBridge' -as [type])) {
        Add-Type -TypeDefinition @'
namespace Craft.Services {
    public static class OrchestratorBridge {
        public static System.Collections.Generic.List<object[]> Calls = new System.Collections.Generic.List<object[]>();
        public static System.Collections.Generic.HashSet<string> ActiveNames = new System.Collections.Generic.HashSet<string>();
        public static bool IsRunActive(string name) { return ActiveNames.Contains(name); }
        public static void QueueOrchestrationFromFile(string name, string batchFilePath, int priority,
            string postExecFunctionName, string postExecParametersJson, string reference, string parentRunName,
            bool sequential, bool allowCollision, int maxConcurrency, bool stopOnFailure) {
            Calls.Add(new object[] { name, parentRunName, allowCollision, priority, sequential, maxConcurrency, stopOnFailure });
            System.IO.File.Delete(batchFilePath);
        }
    }
}
'@
    }

    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) $script:Logs.Add([pscustomobject]@{ Message = $message; Sev = $sev }) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) $script:Rows[$TableName] }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeAll, [switch]$IncludeErrors, [switch]$SkipList) $script:Tenants }
    function New-CippQueueEntry { param($Name, $TotalTasks, $Link, $Reference) @{ RowKey = $script:QueueId } }
    function Get-CIPPSamPermissions { [pscustomobject]@{ Timestamp = [datetime]'2026-01-01' } }
    function Get-TenantGroups { param($Dynamic) [pscustomobject]@{ Name = 'Group'; Id = 'g1' } }
    function Expand-CIPPTenantGroups { param($TenantFilter) [pscustomobject]@{ value = 'AllTenants' } }
    function Get-CippAuditLogPlannedWindows { param($ExistingRows, $Now) [pscustomobject]@{ RowKey = 'w1' } }
    function Get-CippAuditLogReconciliationWindows { param($ExistingRows, $Now) }
    function Test-CIPPRerun { param($TenantFilter, $Type, $API, [switch]$Clear) $false }
    function Get-CIPPDbItem { param($TenantFilter, [switch]$CountsOnly) [pscustomobject]@{ PartitionKey = 'a.onmicrosoft.com'; DataCount = 5 } }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) 'AllTenants' }
    function Push-GetTenants { param($Item) [pscustomobject]@{ FunctionName = 'DomainAnalyserTenant'; customerId = 't1' } }
    function Push-GetApplicationQueue { param($Item) [pscustomobject]@{ Name = 'app'; FunctionName = 'UploadApplication' } }

    # Runs a starter against the fake bridge with the given run names already active.
    function Invoke-Timer ([scriptblock]$Start, [string[]]$Active = @()) {
        [Craft.Services.OrchestratorBridge]::Calls.Clear()
        [Craft.Services.OrchestratorBridge]::ActiveNames.Clear()
        foreach ($Name in $Active) { [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add($Name) }
        $Result = & $Start
        [pscustomobject]@{
            Result = $Result
            Calls  = @([Craft.Services.OrchestratorBridge]::Calls | ForEach-Object { [pscustomobject]@{ Name = $_[0]; AllowCollision = $_[2] } })
        }
    }
}

Describe 'Timer runs that must not overlap themselves' {
    BeforeEach {
        $script:PreviousCippNg = $env:CIPPNG
        $script:PreviousTenantId = $env:TenantID
        $env:CIPPNG = 'true'
        $env:TenantID = 'partner-id'
        $script:Logs = [System.Collections.Generic.List[object]]::new()
        $script:QueueId = [guid]::NewGuid().Guid
        $script:Tenants = @([pscustomobject]@{ customerId = 't1'; defaultDomainName = 'a.onmicrosoft.com'; displayName = 'A'; Excluded = $false })
        $script:Rows = @{
            SchedulerConfig = @([pscustomobject]@{ PartitionKey = 'CippNotifications'; RowKey = 'r1'; type = 'CIPPNotifications'; tenant = 'a.onmicrosoft.com'; tenantid = 't1' })
            WebhookRules    = @([pscustomobject]@{ PartitionKey = 'Webhookv2'; RowKey = 'rule'; Tenants = '[{"value":"AllTenants"}]' })
        }
    }
    AfterEach {
        $env:CIPPNG = $script:PreviousCippNg
        $env:TenantID = $script:PreviousTenantId
    }

    Context '<Label>' -ForEach @(
        @{ Label = 'Scheduler'; Start = { Start-SchedulerOrchestrator }; RunName = 'SchedulerOrchestrator'; WithQueueId = $true }
        @{ Label = 'Table cleanup'; Start = { Start-TableCleanup }; RunName = 'TableCleanup'; WithQueueId = $false }
        @{ Label = 'CPV permissions refresh'; Start = { Start-UpdatePermissionsOrchestrator }; RunName = 'UpdatePermissionsOrchestrator'; WithQueueId = $true }
        @{ Label = 'Dynamic tenant groups, all groups'; Start = { Start-TenantDynamicGroupOrchestrator }; RunName = 'UpdateDynamicTenantGroups'; WithQueueId = $true }
        @{ Label = 'Domain analyser, all tenants'; Start = { Start-DomainOrchestrator -SkipExchangeFilter }; RunName = 'DomainAnalyser_Tenants'; WithQueueId = $true }
        @{ Label = 'App upload timer'; Start = { Start-ApplicationOrchestrator }; RunName = 'ApplicationOrchestrator'; WithQueueId = $false }
        @{ Label = 'Audit log search creation'; Start = { Start-AuditLogSearchCreationV2 }; RunName = 'AuditLogSearchCreationV2'; WithQueueId = $false }
        @{ Label = 'Tests, all tenants'; Start = { Start-CIPPDBTestsRun -TenantFilter 'allTenants' }; RunName = 'TestsList'; WithQueueId = $false }
    ) {
        BeforeEach {
            $script:Active = if ($WithQueueId) { "$RunName-$script:QueueId" } else { $RunName }
        }

        It 'starts with collisions off when nothing of that name is running' {
            $Run = Invoke-Timer -Start $Start

            $Run.Calls.Count | Should -Be 1
            $Run.Calls[0].Name | Should -Be $script:Active
            $Run.Calls[0].AllowCollision | Should -BeFalse
        }

        It 'skips without an error while a run of that name is active' {
            $Run = Invoke-Timer -Start $Start -Active $script:Active

            $Run.Calls.Count | Should -Be 0
            @($script:Logs | Where-Object { $_.Sev -eq 'Error' }) | Should -BeNullOrEmpty
            @($script:Logs | Where-Object { $_.Message -like "Skipped $($script:Active)*still in progress" }).Count | Should -Be 1
        }
    }

    Context 'callers that report the outcome' {
        It 'logs a skipped CPV refresh as skipped, and says so to the caller' {
            $Run = Invoke-Timer -Start { Invoke-ExecCPVRefresh -Request @{} } -Active "UpdatePermissionsOrchestrator-$script:QueueId"

            $Run.Result.Body.Results | Should -BeLike '*already running*skipped'
            @($script:Logs | Where-Object { $_.Message -like 'Skipped CPV permissions refresh*' }).Count | Should -Be 1
            @($script:Logs | Where-Object { $_.Message -like 'Started CPV*' }) | Should -BeNullOrEmpty
        }

        It 'tells the caller an all-tenants domain analyser run was skipped' {
            $Run = Invoke-Timer -Start { Invoke-ExecDomainAnalyser -Request @{ Body = @{} } } -Active "DomainAnalyser_Tenants-$script:QueueId"

            $Run.Result.Body.Results | Should -BeLike '*already running*skipped'
        }

        It 'tells the caller an all-tenants tests run was skipped' {
            $Request = @{ Query = @{ tenantFilter = 'allTenants'; mode = 'tests' } }
            $Run = Invoke-Timer -Start { Invoke-ExecTestRun -Request $Request -TriggerMetadata @{ FunctionName = 'ExecTestRun' } } -Active 'TestsList'

            $Run.Result.StatusCode | Should -Be 200
            $Run.Result.Body.Results | Should -BeLike '*already running*skipped'
        }

        It 'reports a skipped tests run in its result message' {
            $Run = Invoke-Timer -Start { Start-CIPPDBTestsRun -TenantFilter 'allTenants' } -Active 'TestsList'

            $Run.Result.InstanceId | Should -BeLike '*-Skipped'
            $Run.Result.Message | Should -BeLike '*skipped*'
        }
    }

    Context 'manual runs that must still start alongside an active run' {
        It 'starts a single dynamic group while the all-groups run is active' {
            $Run = Invoke-Timer -Start { Start-TenantDynamicGroupOrchestrator -GroupId 'g1' } -Active "UpdateDynamicTenantGroups-$script:QueueId"

            $Run.Calls.Count | Should -Be 1
            $Run.Calls[0].AllowCollision | Should -BeTrue
        }

        It 'starts a single-tenant domain analyser run while the all-tenants run is active' {
            $Run = Invoke-Timer -Start { Start-DomainOrchestrator -TenantFilter 'a.onmicrosoft.com' } -Active 'DomainAnalyser_Tenants'

            $Run.Calls.Count | Should -Be 1
            $Run.Calls[0].AllowCollision | Should -BeTrue
        }

        It 'starts a manual app upload while the timer run is active' {
            $Run = Invoke-Timer -Start { Invoke-ExecAppUpload -Request @{} } -Active 'ApplicationOrchestrator'

            $Run.Calls.Count | Should -Be 1
            $Run.Calls[0].AllowCollision | Should -BeTrue
        }

        It 'starts a single-tenant tests run while the all-tenants run is active' {
            $Run = Invoke-Timer -Start { Start-CIPPDBTestsRun -TenantFilter 'a.onmicrosoft.com' } -Active 'TestsList'

            $Run.Calls.Count | Should -Be 1
            $Run.Calls[0].Name | Should -Be 'TestsList-a.onmicrosoft.com'
            $Run.Calls[0].AllowCollision | Should -BeTrue
        }
    }
}
