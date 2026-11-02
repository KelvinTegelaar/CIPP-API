# A run-now queues Start-UserTasksOrchestrator -TaskId while the task is also due for the 15-minute timer. When the
# starter ran late it claimed the task again whatever its state, so an offboarding the timer had already run ran twice.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Start-UserTasksOrchestrator.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Start-UserTasksOrchestrator.ps1 under Modules/' }

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Get-CIPPScheduledTaskNextRun { param($Recurrence, $ScheduledTime) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $tenantid, $LogData) }
    function Invoke-CIPPOffboardingJob { param($TenantFilter, $Username) }

    . $FunctionPath

    function New-TaskRow {
        param([string]$State, [int]$MinutesAgo = 5)
        [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Offboarding: user@a.onmicrosoft.com'
            Command       = 'Invoke-CIPPOffboardingJob'
            Parameters    = '{}'
            ScheduledTime = '1'
            TaskState     = $State
            Recurrence    = '0'
            Tenant        = 'a.onmicrosoft.com'
            ETag          = 'etag-1'
            Timestamp     = [datetimeoffset]::UtcNow.AddMinutes(-$MinutesAgo)
        }
    }
}

Describe 'Start-UserTasksOrchestrator claim' {
    BeforeEach {
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:Claims = [System.Collections.Generic.List[object]]::new()
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Update-AzDataTableEntity { $script:Claims.Add($Entity) }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'a.onmicrosoft.com'; customerId = 'cust-a' } }
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock Write-LogMessage {}
        Mock Start-CIPPOrchestrator { foreach ($Item in @($InputObject.Batch)) { $script:Started.Add($Item) } }
    }

    It 'does not reclaim a run-now task that is <State>' -ForEach @(
        @{ State = 'Pending' }
        @{ State = 'Running' }
        @{ State = 'Processing' }
        @{ State = 'Completed' }
    ) {
        Mock Get-CIPPAzDataTableEntity { New-TaskRow -State $State }

        Start-UserTasksOrchestrator -TaskId 'task-1'

        $script:Claims.Count | Should -Be 0
        $script:Started.Count | Should -Be 0
    }

    It 'claims a run-now task that is Planned' {
        Mock Get-CIPPAzDataTableEntity { New-TaskRow -State 'Planned' }

        Start-UserTasksOrchestrator -TaskId 'task-1'

        $script:Claims.Count | Should -Be 1
        $script:Claims[0].TaskState | Should -Be 'Pending'
        $script:Started.Count | Should -Be 1
    }

    It 'reclaims a run-now task whose Pending claim is over an hour old' {
        Mock Get-CIPPAzDataTableEntity { New-TaskRow -State 'Pending' -MinutesAgo 90 }

        Start-UserTasksOrchestrator -TaskId 'task-1'

        $script:Started.Count | Should -Be 1
    }

    It 'stamps the dispatch with the ExecutedTime it claimed' {
        Mock Get-CIPPAzDataTableEntity { New-TaskRow -State 'Planned' }

        Start-UserTasksOrchestrator

        $script:Started[0].TaskInfo.ExecutedTime | Should -Be $script:Claims[0].ExecutedTime
    }
}
