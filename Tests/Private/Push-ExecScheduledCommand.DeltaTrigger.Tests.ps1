# Pester tests for the delta trigger path in Push-ExecScheduledCommand
# The delta lookup runs above every try in this function, so a throw there used to escape the
# entrypoint with no result written, leaving the task on the orchestrator's 'Pending' claim to be
# re-picked as a stale claim every hour forever. Pins that a delta failure is recorded on the task,
# that a recurring task stays recurring - including the bare-number recurrences the UI offers - and
# that only ExecutionMode 'once' or a genuinely non-recurring task reaches a terminal state.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ExecScheduledCommand.ps1 under Modules/' }

    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-DeltaQueryUrl { param($TenantFilter, $PartitionKey) }
    function New-GraphDeltaQuery { param($DeltaUrl, $TenantFilter, $PartitionKey) }
    function Test-DeltaQueryConditions { param($Query, $Trigger, $TenantFilter, $LastTrigger) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $tenantid, $message, $sev, $LogData, $headers) }
    function Set-CippScheduledTaskContext { param($TaskId) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSchedulerBlockedCommands { }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Clear-CIPPImmutableID { param($UserID, $TenantFilter, $APIName) }

    . $FunctionPath

    $script:TaskEpoch = 1700000000
    function Get-UnixNow { [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds }

    function New-DeltaTask {
        param([string]$Recurrence = '15m', [string]$ExecutionMode = 'once', [int64]$ScheduledTime = (Get-UnixNow))
        [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Clear Immutable ID: bob'
            Tenant        = 'contoso.com'
            TaskState     = 'Pending'
            Recurrence    = $Recurrence
            ScheduledTime = "$ScheduledTime"
            Command       = 'Clear-CIPPImmutableID'
            Parameters    = '{}'
            Trigger       = "{`"Type`":`"DeltaQuery`",`"DeltaResource`":`"users`",`"ResourceFilter`":[`"user-1`"],`"EventType`":`"deleted`",`"ExecutePerResource`":true,`"ExecutionMode`":`"$ExecutionMode`"}"
        }
    }

    function Invoke-Task {
        param($Task)
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Escaped = $null
        try {
            $null = Push-ExecScheduledCommand -Item ([pscustomobject]@{
                    Command      = $Task.Command
                    Parameters   = [pscustomobject]@{ TenantFilter = 'contoso.com'; UserID = 'user-1' }
                    TaskInfo     = $Task
                    FunctionName = 'ExecScheduledCommand'
                })
        } catch {
            $script:Escaped = $_.Exception.Message
        }
        # The task row write is the last one; earlier writes are the 'Running' transition.
        $script:Writes | Select-Object -Last 1
    }
}

Describe 'Push-ExecScheduledCommand delta trigger' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock -CommandName Get-CippTable -MockWith { @{ Context = $tablename } }
        Mock -CommandName Update-AzDataTableEntity -MockWith { $script:Writes.Add($Entity) }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Set-CippScheduledTaskContext -MockWith { }
        Mock -CommandName Set-CippUserAgentContext -MockWith { }
        Mock -CommandName Send-CIPPScheduledTaskAlert -MockWith { }
        Mock -CommandName Get-CIPPSchedulerBlockedCommands -MockWith { @() }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'customer-guid' } }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Get-AzDataTableEntity -MockWith { [pscustomobject]@{ TaskState = 'Pending' } }
        Mock -CommandName Get-DeltaQueryUrl -MockWith { 'https://graph/deltalink' }
        Mock -CommandName New-GraphDeltaQuery -MockWith { @{ value = @() } }
        Mock -CommandName Test-DeltaQueryConditions -MockWith { @{ ConditionsMet = $false; MatchedData = @() } }
        Mock -CommandName Clear-CIPPImmutableID -MockWith { 'cleared' }
        # The module allow-list check reads Get-Command; only intercept the scheduled command itself
        # so Pester's own use of Get-Command is untouched.
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'Clear-CIPPImmutableID' } -MockWith {
            [pscustomobject]@{ Name = 'Clear-CIPPImmutableID'; Module = 'CIPPCore'; Parameters = @{ TenantFilter = 1; UserID = 1 } }
        }
    }

    Context 'The delta lookup fails' {
        It 'does not let the exception escape the entrypoint' {
            Mock -CommandName Get-DeltaQueryUrl -MockWith { throw 'Delta Query not found.' }

            $null = Invoke-Task -Task (New-DeltaTask)

            $script:Escaped | Should -BeNullOrEmpty
        }

        It 'records the failure on the task instead of leaving it on the Pending claim' {
            Mock -CommandName Get-DeltaQueryUrl -MockWith { throw 'Delta Query not found.' }

            $Final = Invoke-Task -Task (New-DeltaTask)

            $Final.TaskState | Should -Be 'Failed - Planned'
            $Final.Results | Should -BeLike '*Delta Query not found*'
        }

        It 'reschedules one interval out rather than immediately' {
            Mock -CommandName Get-DeltaQueryUrl -MockWith { throw 'Delta Query not found.' }

            $Base = Get-UnixNow
            $Final = Invoke-Task -Task (New-DeltaTask -Recurrence '15m' -ScheduledTime $Base)

            [int64]$Final.ScheduledTime | Should -Be ($Base + 900)
        }

        It 'pulls a long stale schedule forward instead of setting a run time in the past' {
            Mock -CommandName Get-DeltaQueryUrl -MockWith { throw 'Delta Query not found.' }

            $Base = Get-UnixNow
            $Final = Invoke-Task -Task (New-DeltaTask -Recurrence '15m' -ScheduledTime $script:TaskEpoch)

            [int64]$Final.ScheduledTime | Should -BeGreaterOrEqual ($Base + 900)
            [int64]$Final.ScheduledTime | Should -BeLessOrEqual ($Base + 960)
        }

        It 'catches a failure from the delta refresh as well as the lookup' {
            Mock -CommandName New-GraphDeltaQuery -MockWith { throw 'Failed to create Delta Query: Graph outage.' }

            $Final = Invoke-Task -Task (New-DeltaTask)

            $script:Escaped | Should -BeNullOrEmpty
            $Final.TaskState | Should -Be 'Failed - Planned'
        }
    }

    Context 'Recurrence is preserved across a delta failure' {
        BeforeEach {
            Mock -CommandName Get-DeltaQueryUrl -MockWith { throw 'Delta Query not found.' }
        }

        # Bare numbers mean days and are offered by the scheduler UI. The delta block parses
        # Recurrence with its own switch, which did not normalise them, so these went terminal.
        It 'keeps a <Recurrence> task recurring, next run +<Seconds>s' -ForEach @(
            @{ Recurrence = '15m'; Seconds = 900 }
            @{ Recurrence = '4h'; Seconds = 14400 }
            @{ Recurrence = '1d'; Seconds = 86400 }
            @{ Recurrence = '30d'; Seconds = 2592000 }
            @{ Recurrence = '1'; Seconds = 86400 }
            @{ Recurrence = '7'; Seconds = 604800 }
            @{ Recurrence = '30'; Seconds = 2592000 }
        ) {
            $Base = Get-UnixNow
            $Final = Invoke-Task -Task (New-DeltaTask -Recurrence $Recurrence -ScheduledTime $Base)

            $Final.TaskState | Should -Be 'Failed - Planned'
            [int64]$Final.ScheduledTime | Should -Be ($Base + $Seconds)
        }

        It 'retires a <Recurrence> task, which is not recurring' -ForEach @(
            @{ Recurrence = '0' }
            @{ Recurrence = '' }
        ) {
            $Final = Invoke-Task -Task (New-DeltaTask -Recurrence $Recurrence)

            $Final.TaskState | Should -Be 'Failed'
        }
    }

    Context 'The trigger does not fire' {
        It 'reschedules the task and leaves it runnable' {
            $Base = Get-UnixNow
            $Final = Invoke-Task -Task (New-DeltaTask -ScheduledTime $Base)

            $Final.TaskState | Should -Be 'Planned'
            [int64]$Final.ScheduledTime | Should -Be ($Base + 900)
            Should -Invoke Clear-CIPPImmutableID -Times 0 -Exactly
        }
    }

    Context 'The trigger fires' {
        It 'completes an ExecutionMode once task so it never runs again' {
            Mock -CommandName Test-DeltaQueryConditions -MockWith { @{ ConditionsMet = $true; MatchedData = @() } }

            $Final = Invoke-Task -Task (New-DeltaTask -ExecutionMode 'once')

            $Final.TaskState | Should -Be 'Completed'
        }

        It 'reschedules a task that is not ExecutionMode once' {
            Mock -CommandName Test-DeltaQueryConditions -MockWith { @{ ConditionsMet = $true; MatchedData = @() } }

            $Final = Invoke-Task -Task (New-DeltaTask -ExecutionMode 'always')

            $Final.TaskState | Should -Be 'Planned'
        }
    }
}
