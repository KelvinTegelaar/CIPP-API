# Recurrence parsing for scheduled tasks. The orchestrator uses this to close out a run that had no
# tenants in scope; 0 means the task does not repeat and should be completed instead of rescheduled.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')

    function Get-UnixNow { [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds }
}

Describe 'Get-CIPPScheduledTaskNextRun' {
    It 'adds the interval to the last scheduled time' {
        $Last = (Get-UnixNow) - 60
        Get-CIPPScheduledTaskNextRun -Recurrence '1d' -ScheduledTime $Last | Should -Be ($Last + 86400)
    }

    It 'parses minutes and hours' {
        $Last = (Get-UnixNow) - 60
        Get-CIPPScheduledTaskNextRun -Recurrence '30m' -ScheduledTime $Last | Should -Be ($Last + 1800)
        Get-CIPPScheduledTaskNextRun -Recurrence '4h' -ScheduledTime $Last | Should -Be ($Last + 14400)
    }

    It 'treats a bare number as days, the shape older tasks carry' {
        $Last = (Get-UnixNow) - 60
        Get-CIPPScheduledTaskNextRun -Recurrence '7' -ScheduledTime $Last | Should -Be ($Last + 604800)
    }

    It 'returns 0 for a task that does not repeat' {
        Get-CIPPScheduledTaskNextRun -Recurrence '0' -ScheduledTime 1 | Should -Be 0
        Get-CIPPScheduledTaskNextRun -Recurrence $null -ScheduledTime 1 | Should -Be 0
        Get-CIPPScheduledTaskNextRun -Recurrence 'never' -ScheduledTime 1 | Should -Be 0
    }

    It 'does not replay a backlog when the last run is far in the past' {
        # A task stuck or disabled for a year must schedule one run from now, not catch up.
        $Now = Get-UnixNow
        $Next = Get-CIPPScheduledTaskNextRun -Recurrence '1d' -ScheduledTime 1
        $Next | Should -BeGreaterOrEqual ($Now + 86400)
        $Next | Should -BeLessOrEqual ($Now + 86400 + 5)
    }
}
