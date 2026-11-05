# A recurring command can end its own recurrence by setting Recurrence to '0' on its row while it runs
# (Invoke-CIPPIntuneApprovalRetry does once its approval request is resolved). The executor has to read
# that back after the run, or it plans the next run from the recurrence it was dispatched with.

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
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Get-CIPPScheduledTaskNextRun { param($Recurrence, $ScheduledTime) 5000 }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Invoke-CIPPIntuneApprovalRetry { param($TenantFilter) }

    . $FunctionPath

    $script:Item = [pscustomobject]@{
        Command    = 'Invoke-CIPPIntuneApprovalRetry'
        Parameters = @{ TenantFilter = 'a.onmicrosoft.com' }
        TaskInfo   = [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Intune approval'
            Command       = 'Invoke-CIPPIntuneApprovalRetry'
            Tenant        = 'a.onmicrosoft.com'
            Recurrence    = '1h'
            ScheduledTime = '1000'
            TaskState     = 'Planned'
        }
    }
}

Describe 'Push-ExecScheduledCommand recurrence ended by the command' {
    BeforeEach {
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Update-AzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-a' } }
        Mock Write-LogMessage {}
        Mock Invoke-CIPPIntuneApprovalRetry { 'checked' }
        Mock Get-Command { [pscustomobject]@{ Module = 'CIPPCore'; Parameters = @{ TenantFilter = $null } } }
        $script:Item.TaskInfo.Recurrence = '1h'
    }

    It 'completes the task when the command set Recurrence to 0' {
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending'; Recurrence = '0' } }
        Push-ExecScheduledCommand -Item $script:Item

        Should -Invoke Update-AzDataTableEntity -ParameterFilter { $Entity.TaskState -eq 'Completed' } -Times 1 -Exactly
        Should -Invoke Update-AzDataTableEntity -ParameterFilter { $Entity.TaskState -eq 'Planned' } -Times 0 -Exactly
    }

    It 'plans the next run while the recurrence stands' {
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending'; Recurrence = '1h' } }
        Push-ExecScheduledCommand -Item $script:Item

        Should -Invoke Update-AzDataTableEntity -ParameterFilter { $Entity.TaskState -eq 'Planned' -and $Entity.ScheduledTime -eq '5000' } -Times 1 -Exactly
    }
}
