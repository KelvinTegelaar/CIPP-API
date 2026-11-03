function Start-ContainerUpdateCheck {
    <#
    .SYNOPSIS
    Timer function to check for container image updates
    .DESCRIPTION
    Reads update settings from ContainerUpdateSettings table, checks if it's time to run based
    on the configured interval and check time, then runs Invoke-CIPPContainerUpdateCheck.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-ContainerUpdateCheck', 'Check for container image updates')) {
        # Reconcile the stored check result with the running build first — a restart may
        # have applied a previously detected update, and this must clear the stale
        # "update available" flag even when checks are disabled or not yet due. Sync also
        # resolves defaults for never-saved fields (auto-restart on, hourly, 23:00), so
        # only an explicitly saved interval of '0' disables checking.
        $Settings = Sync-CippContainerUpdateState

        if (-not $Settings -or $Settings.CheckInterval -eq '0') {
            Write-Information 'Container update check: disabled'
            return
        }

        # Parse interval to determine if we're due
        $IntervalHours = switch ($Settings.CheckInterval) {
            '1h' { 1 }
            '4h' { 4 }
            '12h' { 12 }
            '1d' { 24 }
            default { 0 }
        }
        if ($IntervalHours -eq 0) {
            Write-Information "Container update check: unknown interval '$($Settings.CheckInterval)'"
            return
        }

        # Check if preferred time applies — within 45 minutes of desired hour using CIPP timezone
        $CheckTime = $Settings.CheckTime
        if ($CheckTime -and [string]$CheckTime -ne '') {
            $TargetHour = [int]$CheckTime

            # Load the configured CIPP timezone (same source as Get-CIPPTimerFunctions)
            $ConfigTable = Get-CIPPTable -tablename Config
            $TimeSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'TimeSettings' and RowKey eq 'TimeSettings'" | Select-Object -First 1
            $ScheduleTimeZone = [TimeZoneInfo]::Utc
            if ($TimeSettings.Timezone) {
                try {
                    $ScheduleTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeSettings.Timezone)
                } catch {
                    Write-Information "Invalid timezone '$($TimeSettings.Timezone)' — falling back to UTC"
                }
            }

            # Convert current UTC time to the configured timezone
            $NowUtc = [DateTime]::UtcNow
            $NowLocal = [TimeZoneInfo]::ConvertTimeFromUtc($NowUtc, $ScheduleTimeZone)
            $Today = $NowLocal.Date
            $TargetTime = $Today.AddHours($TargetHour)
            $MinutesDiff = [math]::Abs(($NowLocal - $TargetTime).TotalMinutes)
            # Handle wrapping around midnight (e.g. target=23, current=0)
            $MinutesDiffWrap = 1440 - $MinutesDiff
            $EffectiveDiff = [math]::Min($MinutesDiff, $MinutesDiffWrap)
            if ($EffectiveDiff -gt 45) {
                Write-Information "Container update check: not within 45 min of preferred time ($($TargetHour):00 $($ScheduleTimeZone.Id)), current local: $($NowLocal.ToString('HH:mm')), diff: $([math]::Round($EffectiveDiff))min"
                return
            }
        }

        # Check if enough time has elapsed since last check
        $LastCheck = $Settings.LastCheck
        if ($LastCheck) {
            try {
                $LastCheckEpoch = [int64]$LastCheck
                $LastCheckTime = [DateTimeOffset]::FromUnixTimeSeconds($LastCheckEpoch).UtcDateTime
                $ElapsedHours = ((Get-Date).ToUniversalTime() - $LastCheckTime).TotalHours
                if ($ElapsedHours -lt ($IntervalHours * 0.9)) {
                    Write-Information "Container update check: last check was $([math]::Round($ElapsedHours, 1))h ago, interval is ${IntervalHours}h — skipping"
                    return
                }
            } catch {
                Write-Information "Container update check: could not parse LastCheck '$LastCheck' — proceeding"
            }
        }

        Write-Information 'Container update check: running'

        try {
            $Check = Invoke-CIPPContainerUpdateCheck -Settings $Settings -APIName 'ContainerUpdateCheck'
            if ($Check.Status -eq 'NoImage') {
                Write-LogMessage -API 'ContainerUpdateCheck' -message 'Could not determine current container image from ARM' -sev Warning
            } elseif ($Check.Status -eq 'NotGHCR') {
                Write-Information "Container update check: skipped - image '$($Check.LinuxFxVersion)' is not hosted on GHCR"
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'ContainerUpdateCheck' -message "Failed to check for container update: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }
}
