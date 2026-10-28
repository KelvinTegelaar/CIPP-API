# A task left Pending for an hour is reclaimed and dispatched again even when the first dispatch was only queued.
# The executor runs a dispatch only while the row still carries the ExecutedTime its claim stamped on it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ExecScheduledCommand.ps1 under Modules/' }

    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Add-CIPPGroupMember { param($TenantFilter, $Member) }

    . $FunctionPath

    function New-DispatchItem {
        param($ClaimedTime)
        $TaskInfo = [pscustomobject]@{
            PartitionKey = 'ScheduledTask'
            RowKey       = 'task-1'
            Name         = 'Add member'
            Command      = 'Add-CIPPGroupMember'
            Tenant       = 'a.onmicrosoft.com'
            Recurrence   = '0'
            TaskState    = 'Planned'
        }
        if ($ClaimedTime) { $TaskInfo | Add-Member -NotePropertyName ExecutedTime -NotePropertyValue $ClaimedTime }
        [pscustomobject]@{ Command = 'Add-CIPPGroupMember'; Parameters = @{ TenantFilter = 'a.onmicrosoft.com'; Member = 'u' }; TaskInfo = $TaskInfo }
    }
}

Describe 'Push-ExecScheduledCommand superseded claim' {
    BeforeEach {
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Update-AzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-a' } }
        Mock Write-LogMessage {}
        Mock Add-CIPPGroupMember { 'Added member' }
        Mock Get-Command {
            [pscustomobject]@{ Module = 'CIPPCore'; Parameters = @{ TenantFilter = $null; Member = $null } }
        }
        Mock Get-AzDataTableEntity {
            [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending'; ExecutedTime = '2000' }
        }
    }

    It 'skips a dispatch whose claim was superseded' {
        Push-ExecScheduledCommand -Item (New-DispatchItem -ClaimedTime '1000')

        Should -Invoke Add-CIPPGroupMember -Times 0 -Exactly
        Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly
    }

    It 'runs the dispatch of the current claim' {
        Push-ExecScheduledCommand -Item (New-DispatchItem -ClaimedTime '2000')

        Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly
    }

    It 'runs a dispatch queued before claims were stamped' {
        Push-ExecScheduledCommand -Item (New-DispatchItem)

        Should -Invoke Add-CIPPGroupMember -Times 1 -Exactly
    }
}
