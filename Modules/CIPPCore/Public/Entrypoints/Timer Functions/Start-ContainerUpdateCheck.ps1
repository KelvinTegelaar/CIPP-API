function Start-ContainerUpdateCheck {
    <#
    .SYNOPSIS
    Timer function to check for container image updates
    .DESCRIPTION
    Reads update settings from ContainerUpdateSettings table, checks if it's time to run based
    on the configured interval and check time, queries GHCR for the latest image digest, and
    optionally triggers a restart if auto-update is enabled.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-ContainerUpdateCheck', 'Check for container image updates')) {
        $SettingsTable = Get-CippTable -tablename 'ContainerUpdateSettings'
        $Settings = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1

        if (-not $Settings -or $Settings.CheckInterval -eq '0' -or [string]::IsNullOrWhiteSpace($Settings.CheckInterval)) {
            Write-Information 'Container update check: disabled or not configured'
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
            # Resolve ARM site details
            $Subscription = Get-CIPPAzFunctionAppSubId
            $SiteName = $env:WEBSITE_SITE_NAME
            $RGName = $env:WEBSITE_RESOURCE_GROUP
            if (-not $RGName) {
                $Owner = $env:WEBSITE_OWNER_NAME
                if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                    $RGName = $Matches.RGName
                }
            }

            $ImageTag = $env:IMAGE_TAG ?? 'unknown'
            $CurrentImage = $null

            if ($Subscription -and $RGName -and $SiteName) {
                $apiVersion = '2024-11-01'
                $uri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/config/web?api-version=$apiVersion"
                $webConfig = New-CIPPAzRestRequest -Uri $uri -Method GET
                $linuxFxVersion = $webConfig.properties.linuxFxVersion
                if ($linuxFxVersion) {
                    $CurrentImage = $linuxFxVersion -replace '^DOCKER\|', ''
                }
            }

            if (-not $CurrentImage) {
                Write-LogMessage -API 'ContainerUpdateCheck' -message 'Could not determine current container image from ARM' -sev Warning
                return
            }

            # Update checking only works with GHCR-hosted images
            if ($CurrentImage -notmatch '^ghcr\.io/') {
                Write-Information "Container update check: skipped — image '$CurrentImage' is not hosted on GHCR"
                return
            }

            $CheckTag = if ($CurrentImage -match ':([^:]+)$') { $Matches[1] } else { $ImageTag }

            # Parse image path for GHCR
            $imagePath = $CurrentImage -replace '^ghcr\.io/', '' -replace ':.*$', ''
            if (-not $imagePath) {
                Write-LogMessage -API 'ContainerUpdateCheck' -message 'Could not parse image path from reference' -sev Warning
                return
            }

            # Get anonymous GHCR token
            $tokenUri = "https://ghcr.io/token?scope=repository:${imagePath}:pull"
            $tokenResp = Invoke-RestMethod -Uri $tokenUri -Method GET -ErrorAction Stop
            $token = $tokenResp.token

            $digestHeaders = @{
                Authorization = "Bearer $token"
                Accept        = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'
            }

            # Get remote digest for the configured channel tag
            $manifestUri = "https://ghcr.io/v2/$imagePath/manifests/$CheckTag"
            $resp = Invoke-WebRequest -Uri $manifestUri -Method HEAD -Headers $digestHeaders -ErrorAction Stop
            $RemoteDigest = $resp.Headers['Docker-Content-Digest']
            if ($RemoteDigest -is [array]) { $RemoteDigest = $RemoteDigest[0] }

            # Get running digest for the baked-in image tag
            $RunningDigest = $null
            try {
                $runningUri = "https://ghcr.io/v2/$imagePath/manifests/$ImageTag"
                $runResp = Invoke-WebRequest -Uri $runningUri -Method HEAD -Headers $digestHeaders -ErrorAction Stop
                $RunningDigest = $runResp.Headers['Docker-Content-Digest']
                if ($RunningDigest -is [array]) { $RunningDigest = $RunningDigest[0] }
            } catch {
                Write-Information "Could not get running digest for tag $ImageTag"
            }

            $UpdateAvailable = $false
            if ($RemoteDigest -and $RunningDigest -and $RemoteDigest -ne $RunningDigest) {
                $UpdateAvailable = $true
            }

            # Update the settings row with results (preserve user settings)
            $UpdateEntity = @{
                PartitionKey    = 'Settings'
                RowKey          = 'UpdateConfig'
                AutoUpdate      = [string]($Settings.AutoUpdate ?? 'false')
                CheckInterval   = [string]($Settings.CheckInterval ?? '0')
                CheckTime       = [string]($Settings.CheckTime ?? '')
                LastCheck       = [string][int64](([DateTimeOffset]::UtcNow).ToUnixTimeSeconds())
                UpdateAvailable = [string]$UpdateAvailable
                RunningDigest   = [string]($RunningDigest ?? '')
                RemoteDigest    = [string]($RemoteDigest ?? '')
            }
            Add-CIPPAzDataTableEntity @SettingsTable -Entity $UpdateEntity -Force | Out-Null

            if ($UpdateAvailable -and $Settings.AutoUpdate -eq 'true') {
                Write-LogMessage -API 'ContainerUpdateCheck' -message "Auto-update: new container image detected (running: $RunningDigest, remote: $RemoteDigest). Restarting." -sev Info
                try {
                    [Craft.Services.AppLifecycleBridge]::RequestRestart('Auto-update: new container image available')
                } catch {
                    Write-LogMessage -API 'ContainerUpdateCheck' -message 'Auto-restart requested but AppLifecycleBridge is not available' -sev Warning
                }
            } elseif ($UpdateAvailable) {
                Write-LogMessage -API 'ContainerUpdateCheck' -message "Container update available (running: $RunningDigest, remote: $RemoteDigest)" -sev Info
            } else {
                Write-Information "Container is up to date. Digest: $RunningDigest"
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'ContainerUpdateCheck' -message "Failed to check for container update: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }
}
