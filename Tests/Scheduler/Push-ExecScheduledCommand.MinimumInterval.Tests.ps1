# An alert's catalog entry can set minimumRunInterval. A task saved with a shorter recurrence keeps its schedule, but
# a run whose slot (ScheduledTime) is sooner than the minimum after the tenant's last completed slot is skipped and
# recorded as Skipped. Slots, not pickup times, so a late pickup does not drift later runs. Every run of a scripted
# alert is recorded in the run history with what it found.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')

    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Add-CIPPAlertRunHistory { param($Task, $Tenant, $TenantId, $Outcome, $Summary, $Counts, $StartedUtc, $ScheduledUtc, $DurationMs, [switch]$RecordCompletion) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-CIPPAlertBreachAlert { param($TenantFilter, $InputValue, $Headers) }
    function Get-CIPPAlertNoMinimum { param($TenantFilter, $InputValue, $Headers) }

    . $FunctionPath

    # Today's 02:00 UTC slot, the one this run is due for, however late a worker picks it up.
    $script:Slot = [datetime]::UtcNow.Date.AddHours(2)

    function New-AlertItem ([string]$Command, [string]$Recurrence) {
        $TaskInfo = [pscustomobject]@{
            PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; Name = 'Breach alert'; Command = $Command
            Tenant = 'contoso.onmicrosoft.com'; Recurrence = $Recurrence; TaskState = 'Pending'
            ScheduledTime = [string][datetimeoffset]::new($script:Slot).ToUnixTimeSeconds()
        }
        [pscustomobject]@{ Command = $Command; Parameters = @{ TenantFilter = 'contoso.onmicrosoft.com' }; TaskInfo = $TaskInfo }
    }
}

Describe 'Push-ExecScheduledCommand minimum alert interval' {
    BeforeAll {
        $script:PreviousRoot = $env:CIPPRootPath
        $env:CIPPRootPath = $TestDrive
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Config') -Force | Out-Null
        '[{"name":"BreachAlert","minimumRunInterval":"1d"},{"name":"NoMinimum"}]' | Set-Content -Path (Join-Path $TestDrive 'Config/alerts.json')
    }
    AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

    BeforeEach {
        $script:Holder = $null
        $script:LastCompleted = $null
        Mock Set-CippScheduledTaskContext { $script:Holder = $AlertRun }
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Update-AzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1' } }
        Mock Write-LogMessage {}
        Mock Send-CIPPScheduledTaskAlert {}
        Mock Add-CIPPAlertRunHistory {}
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending' } }
        Mock Get-CIPPAzDataTableEntity { if ($script:LastCompleted) { [pscustomobject]@{ LastSlotUtc = $script:LastCompleted.ToString('o') } } }
        Mock Get-Command { [pscustomobject]@{ Module = 'CIPPAlerts'; Parameters = @{ TenantFilter = 1; InputValue = 1; Headers = 1 } } }
        Mock Get-CIPPAlertBreachAlert { $script:Holder.New = 2; $script:Holder.Continuing = 5; $script:Holder.Reported = $true }
        Mock Get-CIPPAlertNoMinimum {}
    }

    It 'skips a run within the minimum, records it as Skipped and moves the task to its next slot' {
        $script:LastCompleted = $script:Slot.AddHours(-2)
        $Result = Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertBreachAlert' '1h') 6>$null

        $Result | Should -BeLike 'Task Skipped*'
        Should -Invoke Get-CIPPAlertBreachAlert -Times 0
        Should -Invoke Add-CIPPAlertRunHistory -Times 1 -Exactly -ParameterFilter { $Outcome -eq 'Skipped' -and $Summary -like '*at most every 1d*' -and $TenantId -eq 'cust-1' }
        Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.TaskState -eq 'Planned' -and [int64]$Entity.ScheduledTime -gt [datetimeoffset]::new($script:Slot).ToUnixTimeSeconds() }
    }

    It 'runs the slot one minimum after the last completed slot, even when that one was picked up late' {
        # Yesterday's 02:00 slot completed (its worker may have started at 02:20); the marker holds the slot.
        $script:LastCompleted = $script:Slot.AddDays(-1)
        Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertBreachAlert' '1h') 6>$null | Out-Null

        Should -Invoke Get-CIPPAlertBreachAlert -Times 1 -Exactly
        Should -Invoke Add-CIPPAlertRunHistory -Times 1 -Exactly -ParameterFilter {
            $Outcome -eq 'Completed' -and $RecordCompletion -and $Summary -like '2 new, 0 reopened, 5 continuing*' -and $ScheduledUtc -eq $script:Slot
        }
    }

    It 'skips the slot just before a full minimum has passed' {
        $script:LastCompleted = $script:Slot.AddDays(-1).AddHours(1)
        Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertBreachAlert' '1h') 6>$null | Out-Null
        Should -Invoke Get-CIPPAlertBreachAlert -Times 0
    }

    It 'runs the first time, when there is no completed run yet' {
        Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertBreachAlert' '1h') 6>$null | Out-Null
        Should -Invoke Get-CIPPAlertBreachAlert -Times 1 -Exactly
    }

    It 'does not check the last run when the saved recurrence already meets the minimum' {
        $script:LastCompleted = $script:Slot.AddHours(-2)
        Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertBreachAlert' '7d') 6>$null | Out-Null

        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
        Should -Invoke Get-CIPPAlertBreachAlert -Times 1 -Exactly
    }

    It 'records an alert without a minimum but stamps no completion, and calls an unreported run Not reported' {
        Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertNoMinimum' '1h') 6>$null | Out-Null

        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
        Should -Invoke Add-CIPPAlertRunHistory -Times 1 -Exactly -ParameterFilter { $Outcome -eq 'Not reported' -and -not $RecordCompletion }
    }

    It 'records a run whose command throws as Failed' {
        Mock Get-CIPPAlertNoMinimum { throw 'Graph said no' }
        Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertNoMinimum' '1h') 6>$null | Out-Null

        Should -Invoke Add-CIPPAlertRunHistory -Times 1 -Exactly -ParameterFilter { $Outcome -eq 'Failed' -and $Summary -like '*Graph said no*' }
    }
}
