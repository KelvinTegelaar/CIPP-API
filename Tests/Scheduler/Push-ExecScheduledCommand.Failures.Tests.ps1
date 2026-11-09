# A scheduled task whose command throws, whose results cannot be stored, or whose per-resource runs all fail must end
# as Failed (one-off, empty recurrence, or a trigger that fires once) or Failed - Planned (recurring), with the error
# in its results, an error log entry instead of the success entry, and a return value that the multi-tenant
# aggregation counts as a failed tenant. The inner catch used to set a state that only the orchestrator branch read,
# so every failed task was written as Completed / Planned and logged as "Successfully executed task".
# The notification step after a failure is kept: a failed run still reaches the task's webhook, email or PSA.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ExecScheduledCommand.ps1 under Modules/' }

    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter, $Property) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Get-CIPPScheduledTaskNextRun { param($Recurrence, $ScheduledTime) 5000 }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Get-DeltaQueryUrl { param($TenantFilter, $PartitionKey) }
    function New-GraphDeltaQuery { param($DeltaUrl, $TenantFilter, $PartitionKey) }
    function Test-DeltaQueryConditions { param($Query, $Trigger, $TenantFilter, $LastTrigger) }
    # The executor only runs functions from the CIPP modules, so the command lives in a module of that name.
    $null = New-Module -Name CIPPCore -ScriptBlock { function Clear-CIPPImmutableID { param($UserID, $TenantFilter) } } | Import-Module -Force -PassThru

    . $FunctionPath

    function New-TaskItem {
        param([string]$Recurrence = '0', [string]$ExecutionMode, [string]$PostExecution = '')
        $TaskInfo = [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Clear immutable ID'
            Command       = 'Clear-CIPPImmutableID'
            Tenant        = 'a.onmicrosoft.com'
            Recurrence    = $Recurrence
            ScheduledTime = '1000'
            TaskState     = 'Pending'
            PostExecution = $PostExecution
        }
        if ($ExecutionMode) {
            $Trigger = @{ Type = 'DeltaQuery'; ExecutePerResource = $true; ExecutionMode = $ExecutionMode }
            $TaskInfo | Add-Member -NotePropertyName Trigger -NotePropertyValue ($Trigger | ConvertTo-Json -Compress)
        }
        [pscustomobject]@{
            Command    = 'Clear-CIPPImmutableID'
            Parameters = @{ TenantFilter = 'a.onmicrosoft.com'; UserID = '%id%' }
            TaskInfo   = $TaskInfo
        }
    }
}

AfterAll {
    Remove-Module -Name CIPPCore -Force -ErrorAction SilentlyContinue
}

Describe 'Push-ExecScheduledCommand failure outcomes' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending' } }
        Mock Update-AzDataTableEntity { $script:Writes.Add($Entity) }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-a' } }
        Mock Get-CippException { @{ NormalizedError = $Exception.Exception.Message } }
        Mock Write-LogMessage {}
        Mock Send-CIPPScheduledTaskAlert {}
        Mock Get-DeltaQueryUrl { 'https://graph.example/delta' }
        Mock New-GraphDeltaQuery { @{ value = @() } }
        Mock Test-DeltaQueryConditions { @{ ConditionsMet = $true; MatchedData = @(@{ id = 'bad' }, @{ id = 'good' }) } }
        Mock Clear-CIPPImmutableID { 'Cleared' }
    }

    Context 'The command throws' {
        It 'records a task with recurrence "<Recurrence>" as <Expected>' -ForEach @(
            @{ Recurrence = '0'; Expected = 'Failed' }
            @{ Recurrence = ''; Expected = 'Failed' }
            @{ Recurrence = '1h'; Expected = 'Failed - Planned' }
        ) {
            Mock Clear-CIPPImmutableID { throw 'command failure' }

            $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence $Recurrence)

            $Result | Should -Be 'Task Failed.'
            $script:Writes[-1].TaskState | Should -Be $Expected
            $script:Writes[-1].Results | Should -BeLike '*Task Failed: command failure*'
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like 'Successfully executed task*' }
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like 'Failed to execute task*command failure*' }
        }

        It 'advances a recurring task to its next slot' {
            Mock Clear-CIPPImmutableID { throw 'command failure' }

            $null = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence '1h')

            $script:Writes[-1].TaskState | Should -Be 'Failed - Planned'
            $script:Writes[-1].ScheduledTime | Should -Be '5000'
        }

        It 'still sends the results to the post-execution targets' {
            Mock Clear-CIPPImmutableID { throw 'command failure' }

            $null = Push-ExecScheduledCommand -Item (New-TaskItem -PostExecution 'Webhook')

            Should -Invoke Send-CIPPScheduledTaskAlert -Times 1 -Exactly
        }
    }

    Context 'The results cannot be stored' {
        BeforeEach {
            # Results over 64000 characters go to the results table, which is unavailable here.
            Mock Clear-CIPPImmutableID { 'x' * 70000 }
            Mock Add-CIPPAzDataTableEntity { throw 'storage unavailable' }
        }

        It 'records the task as <Expected> (recurrence "<Recurrence>", mode "<Mode>") with the error' -ForEach @(
            @{ Recurrence = '0'; Mode = $null; Expected = 'Failed' }
            @{ Recurrence = ''; Mode = $null; Expected = 'Failed' }
            @{ Recurrence = '1h'; Mode = $null; Expected = 'Failed - Planned' }
            @{ Recurrence = '1h'; Mode = 'once'; Expected = 'Failed' }
        ) {
            if ($Mode) { Mock Test-DeltaQueryConditions { @{ ConditionsMet = $true; MatchedData = @(@{ id = 'one' }) } } }

            $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence $Recurrence -ExecutionMode $Mode)

            $Result | Should -Be 'Task Failed.'
            $script:Writes[-1].TaskState | Should -Be $Expected
            $script:Writes[-1].Results | Should -Be 'storage unavailable'
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like 'Successfully executed task*' }
        }

        It 'never writes a re-queued state for a non-recurring task' {
            $null = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence '')

            $script:Writes.TaskState | Should -Not -Contain 'Failed - Planned'
            $script:Writes.TaskState | Should -Not -Contain 'Planned'
        }
    }

    Context 'A trigger task runs per resource' {
        It 'keeps one failed resource in the results and leaves the task planned' {
            Mock Clear-CIPPImmutableID { if ($UserID -eq 'bad') { throw 'resource failure' } "Cleared $UserID" }

            $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence '15m' -ExecutionMode 'always')

            $Result | Should -Be 'Task Completed Successfully.'
            $script:Writes[-1].TaskState | Should -Be 'Planned'
            $script:Writes[-1].Results | Should -BeLike '*Task Failed: resource failure*'
            $script:Writes[-1].Results | Should -BeLike '*Cleared good*'
        }

        It 'records the task as <Expected> when every resource fails (mode "<Mode>")' -ForEach @(
            @{ Mode = 'always'; Expected = 'Failed - Planned' }
            @{ Mode = 'once'; Expected = 'Failed' }
        ) {
            Mock Clear-CIPPImmutableID { throw 'resource failure' }

            $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence '15m' -ExecutionMode $Mode)

            $Result | Should -Be 'Task Failed.'
            $script:Writes[-1].TaskState | Should -Be $Expected
            $script:Writes[-1].Results | Should -BeLike '*Task Failed: resource failure*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like 'Failed to execute task*' }
        }

        It 'completes a once trigger that matched nothing' {
            Mock Test-DeltaQueryConditions { @{ ConditionsMet = $true; MatchedData = @() } }

            $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence '15m' -ExecutionMode 'once')

            $Result | Should -Be 'Task Completed Successfully.'
            $script:Writes[-1].TaskState | Should -Be 'Completed'
        }
    }

    Context 'The command succeeds' {
        It 'still records the task as <Expected> with recurrence "<Recurrence>" and logs the success' -ForEach @(
            @{ Recurrence = '0'; Expected = 'Completed' }
            @{ Recurrence = '1h'; Expected = 'Planned' }
        ) {
            $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence $Recurrence)

            $Result | Should -Be 'Task Completed Successfully.'
            $script:Writes[-1].TaskState | Should -Be $Expected
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like 'Successfully executed task*' }
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
        }
    }
}
