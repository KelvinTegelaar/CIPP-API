# Craft evaluates every timer in CraftTZ only when ApplyTZOffset is on, and delays each firing by a fixed per-site
# share of JitterMinutes. These pin the schedule decisions that rely on both.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $RepoRoot = Split-Path -Parent $BackendRoot
    if (-not ('Cronos.CronExpression' -as [type])) { Add-Type -Path (Join-Path $BackendRoot 'Shared/Cronos/Cronos.dll') }

    $script:Timers = Get-Content -Raw (Join-Path $BackendRoot 'Config/CIPPTimers.json') | ConvertFrom-Json
    $script:Timer = { param($Name) foreach ($T in $script:Timers) { if ($T.Command -eq $Name) { return $T } } }
    $script:Jitter = { param($T) [int]($T.JitterMinutes ?? 0) }
    $script:Cron = { param($T) [Cronos.CronExpression]::Parse($T.Cron, [Cronos.CronFormat]::IncludeSeconds) }
    # A fixed UTC day: relative order is what matters, and every timer shares one timezone
    $script:Day = [DateTimeOffset]::new(2026, 6, 1, 0, 0, 0, [TimeSpan]::Zero)
    $script:FirstSlot = { param($T) (& $script:Cron $T).GetNextOccurrence($script:Day, [TimeZoneInfo]::Utc, $true) }

    $script:AppSettings = foreach ($Name in 'Production', 'Development', 'Local.Development') {
        [pscustomobject]@{ Name = $Name; Json = Get-Content -Raw (Join-Path $RepoRoot "build/config/appsettings.$Name.json") | ConvertFrom-Json }
    }
}

Describe 'Timer schedule' {
    It 'evaluates every timer in the configured timezone (<Name>)' -ForEach @(
        @{ Name = 'Production' }, @{ Name = 'Development' }, @{ Name = 'Local.Development' }
    ) {
        $Settings = @($script:AppSettings).Where({ $_.Name -eq $Name })[0].Json
        $Settings.App.Scheduler.ApplyTZOffset | Should -BeTrue -Because 'without it every timer lacking TZOffset runs on UTC even when CraftTZ is set'
    }

    It 'keeps every jitter window shorter than the gap between its timer''s slots' {
        $Offenders = foreach ($T in @($script:Timers).Where({ (& $script:Jitter $_) -gt 0 })) {
            $Slots = @((& $script:Cron $T).GetOccurrences($script:Day, $script:Day.AddDays(15), [TimeZoneInfo]::Utc))
            $Gap = (1..($Slots.Count - 1) | ForEach-Object { ($Slots[$_] - $Slots[$_ - 1]).TotalMinutes } | Measure-Object -Minimum).Minimum
            if ((& $script:Jitter $T) -ge $Gap) { "$($T.Command): JitterMinutes $(& $script:Jitter $T) >= $Gap minute gap" }
        }
        $Offenders | Should -BeNullOrEmpty
    }

    It '<Command> fires when it is due, without jitter' -ForEach @(
        @{ Command = 'Start-UserTasksOrchestrator' }, @{ Command = 'Start-SchedulerOrchestrator' }, @{ Command = 'Start-AuditLogPlannerV2' },
        @{ Command = 'Start-InstanceHealthSample' }, @{ Command = 'Start-DurableCleanup' }, @{ Command = 'Get-Tenants' }
    ) {
        foreach ($T in @($script:Timers).Where({ $_.Command -eq $Command })) { & $script:Jitter $T | Should -Be 0 }
    }

    It '<Later> fires after <Earlier> on every site' -ForEach @(
        @{ Earlier = 'Start-IntuneReportExportOrchestrator'; Later = 'Start-CIPPDBCacheOrchestrator' }
        @{ Earlier = 'Start-CIPPDBCacheOrchestrator'; Later = 'Start-TestsOrchestrator' }
        @{ Earlier = 'Start-UpdatePermissionsOrchestrator'; Later = 'Start-CIPPPermissionCheck' }
        @{ Earlier = 'Start-StandardsOrchestrator'; Later = 'Start-DriftStandardsOrchestrator' }
    ) {
        $A = & $script:Timer $Earlier; $B = & $script:Timer $Later
        # Every site waits the same share of each window, so a later slot with at least the earlier jitter keeps its gap
        (& $script:Jitter $B) | Should -BeGreaterOrEqual (& $script:Jitter $A)
        (& $script:FirstSlot $B) | Should -BeGreaterThan (& $script:FirstSlot $A)
    }

    It 'keeps the container update check within its 45 minutes of 23:00' {
        $T = & $script:Timer 'Start-ContainerUpdateCheck'
        $Minute = (& $script:FirstSlot $T).Minute
        foreach ($Fire in $Minute, ($Minute + (& $script:Jitter $T))) {
            [Math]::Min($Fire, 60 - $Fire) | Should -BeLessOrEqual 45
        }
    }
}
