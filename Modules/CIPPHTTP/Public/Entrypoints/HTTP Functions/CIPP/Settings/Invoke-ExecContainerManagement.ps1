function Invoke-ExecContainerManagement {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Query.Action ?? $Request.Body.Action

    $ValidChannels = @('latest', 'dev', 'nightly')
    $SettingsTable = Get-CippTable -tablename 'ContainerUpdateSettings'

    # Helper: resolve ARM site details
    function Get-ContainerSiteInfo {
        $info = @{
            Subscription = Get-CIPPAzFunctionAppSubId
            SiteName     = $env:WEBSITE_SITE_NAME
            RGName       = $env:WEBSITE_RESOURCE_GROUP
        }
        if (-not $info.RGName) {
            $Owner = $env:WEBSITE_OWNER_NAME
            if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                $info.RGName = $Matches.RGName
            }
        }
        return $info
    }

    # Helper: query GHCR for the image digest of a given tag
    function Get-GHCRImageDigest {
        param([string]$ImageRef, [string]$Tag)

        # Parse image reference: ghcr.io/owner/repo or owner/repo
        $imagePath = $ImageRef -replace '^ghcr\.io/', '' -replace ':.*$', ''
        if (-not $imagePath) { throw 'Could not parse image path from reference' }

        # Get anonymous token for GHCR (public packages)
        $tokenUri = "https://ghcr.io/token?scope=repository:${imagePath}:pull"
        $tokenResp = Invoke-RestMethod -Uri $tokenUri -Method GET -ErrorAction Stop
        $token = $tokenResp.token

        # Get manifest digest via HEAD request
        $manifestUri = "https://ghcr.io/v2/$imagePath/manifests/$Tag"
        $digestHeaders = @{
            Authorization = "Bearer $token"
            Accept        = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'
        }
        $resp = Invoke-WebRequest -Uri $manifestUri -Method HEAD -Headers $digestHeaders -ErrorAction Stop
        $digest = $resp.Headers['Docker-Content-Digest']
        if ($digest -is [array]) { $digest = $digest[0] }
        return [string]$digest
    }

    switch ($Action) {
        'Status' {
            try {
                $CurrentVersion = $env:APP_VERSION ?? 'unknown'
                $CommitSha = $env:COMMIT_SHA ?? 'unknown'
                $ImageTag = $env:IMAGE_TAG ?? 'unknown'
                $CurrentChannel = $ImageTag

                # Read the full container image reference from ARM
                $CurrentImage = 'unknown'
                $ConfiguredChannel = $CurrentChannel
                $site = Get-ContainerSiteInfo
                if ($site.Subscription -and $site.RGName -and $site.SiteName) {
                    try {
                        $apiVersion = '2024-11-01'
                        $uri = "https://management.azure.com/subscriptions/$($site.Subscription)/resourceGroups/$($site.RGName)/providers/Microsoft.Web/sites/$($site.SiteName)/config/web?api-version=$apiVersion"
                        $webConfig = New-CIPPAzRestRequest -Uri $uri -Method GET
                        $linuxFxVersion = $webConfig.properties.linuxFxVersion
                        if ($linuxFxVersion) {
                            $CurrentImage = $linuxFxVersion -replace '^DOCKER\|', ''
                            if ($CurrentImage -match ':([^:]+)$') {
                                $ConfiguredChannel = $Matches[1]
                            }
                        }
                    } catch {
                        Write-Information "Could not read container config from ARM: $_"
                    }
                }

                # Read update settings and last check result
                $Settings = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                $UpdateInfo = @{
                    AutoUpdate       = $false
                    CheckInterval    = '0'
                    CheckTime        = $null
                    LastCheck        = $null
                    UpdateAvailable  = $false
                    RunningDigest    = $null
                    RemoteDigest     = $null
                }
                if ($Settings) {
                    $UpdateInfo.AutoUpdate = $Settings.AutoUpdate -eq 'true'
                    $UpdateInfo.CheckInterval = $Settings.CheckInterval ?? '0'
                    $UpdateInfo.CheckTime = $Settings.CheckTime ?? $null
                    $UpdateInfo.LastCheck = if ($Settings.LastCheck) { [int64]$Settings.LastCheck } else { $null }
                    $UpdateInfo.UpdateAvailable = $Settings.UpdateAvailable -eq 'true'
                    $UpdateInfo.RunningDigest = $Settings.RunningDigest ?? $null
                    $UpdateInfo.RemoteDigest = $Settings.RemoteDigest ?? $null
                }

                $Body = @{
                    Results = @{
                        CurrentVersion    = $CurrentVersion
                        CommitSha         = $CommitSha
                        ImageTag          = $ImageTag
                        CurrentChannel    = $CurrentChannel
                        ConfiguredChannel = $ConfiguredChannel
                        CurrentImage      = $CurrentImage
                        SiteName          = $site.SiteName
                        ValidChannels     = $ValidChannels
                        UpdateSettings    = $UpdateInfo
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to get container status: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        'CheckUpdate' {
            try {
                $site = Get-ContainerSiteInfo
                $ImageTag = $env:IMAGE_TAG ?? 'unknown'

                # Get the current image reference from ARM
                $CurrentImage = $null
                if ($site.Subscription -and $site.RGName -and $site.SiteName) {
                    $apiVersion = '2024-11-01'
                    $uri = "https://management.azure.com/subscriptions/$($site.Subscription)/resourceGroups/$($site.RGName)/providers/Microsoft.Web/sites/$($site.SiteName)/config/web?api-version=$apiVersion"
                    $webConfig = New-CIPPAzRestRequest -Uri $uri -Method GET
                    $linuxFxVersion = $webConfig.properties.linuxFxVersion
                    if ($linuxFxVersion) {
                        $CurrentImage = $linuxFxVersion -replace '^DOCKER\|', ''
                    }
                }
                if (-not $CurrentImage) {
                    throw 'Could not determine current container image from ARM config'
                }

                # Update checking only works with GHCR-hosted images
                if ($CurrentImage -notmatch '^ghcr\.io/') {
                    $Body = @{
                        Results = @{
                            Message         = "Update checking is only supported for GHCR-hosted images. Current image: $CurrentImage"
                            UpdateAvailable = $false
                            RunningDigest   = $null
                            RemoteDigest    = $null
                            CheckedTag      = $null
                        }
                    }
                    break
                }

                # Determine the tag to check
                $CheckTag = if ($CurrentImage -match ':([^:]+)$') { $Matches[1] } else { $ImageTag }

                # Query GHCR for the remote digest
                $RemoteDigest = Get-GHCRImageDigest -ImageRef $CurrentImage -Tag $CheckTag

                # Get the running container's digest — query for the baked-in tag to get what we're running
                $RunningDigest = $null
                try {
                    $RunningDigest = Get-GHCRImageDigest -ImageRef $CurrentImage -Tag $ImageTag
                } catch {
                    Write-Information "Could not get running digest for tag $ImageTag — may be first check"
                }

                $UpdateAvailable = $false
                if ($RemoteDigest -and $RunningDigest -and $RemoteDigest -ne $RunningDigest) {
                    $UpdateAvailable = $true
                }

                # Store result
                $Entity = @{
                    PartitionKey    = 'Settings'
                    RowKey          = 'UpdateConfig'
                    LastCheck       = [string][int64](([DateTimeOffset]::UtcNow).ToUnixTimeSeconds())
                    UpdateAvailable = [string]$UpdateAvailable
                    RunningDigest   = [string]($RunningDigest ?? '')
                    RemoteDigest    = [string]($RemoteDigest ?? '')
                }
                # Merge with existing settings (preserve AutoUpdate, CheckInterval, CheckTime)
                $Existing = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                if ($Existing) {
                    $Entity.AutoUpdate = $Existing.AutoUpdate ?? 'false'
                    $Entity.CheckInterval = $Existing.CheckInterval ?? '0'
                    $Entity.CheckTime = $Existing.CheckTime ?? ''
                }
                Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null

                # Auto-restart if enabled and update is available
                $Settings = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                if ($UpdateAvailable -and $Settings.AutoUpdate -eq 'true') {
                    Write-LogMessage -API $APIName -headers $Headers -message "Auto-update: new container image detected (running: $RunningDigest, remote: $RemoteDigest). Restarting." -sev Info
                    try { [Craft.Services.AppLifecycleBridge]::RequestRestart('Auto-update: new container image available') } catch {}
                    $Result = "Update available — container restart initiated (auto-update enabled). Running digest: $RunningDigest, Remote digest: $RemoteDigest"
                } elseif ($UpdateAvailable) {
                    $Result = "Update available. Running digest: $RunningDigest, Remote digest: $RemoteDigest. Restart the container to apply."
                    Write-LogMessage -API $APIName -headers $Headers -message "Container update available (running: $RunningDigest, remote: $RemoteDigest)" -sev Info
                } else {
                    $Result = "Container is up to date. Digest: $RunningDigest"
                }
                $Body = @{
                    Results = @{
                        Message         = $Result
                        UpdateAvailable = $UpdateAvailable
                        RunningDigest   = $RunningDigest
                        RemoteDigest    = $RemoteDigest
                        CheckedTag      = $CheckTag
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to check for update: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        'SaveUpdateSettings' {
            try {
                $AutoUpdate = [bool]($Request.Body.AutoUpdate)
                $CheckInterval = $Request.Body.CheckInterval ?? '0'
                $CheckTime = $Request.Body.CheckTime
                $ValidIntervals = @('0', '1h', '4h', '12h', '1d')
                if ($CheckInterval -notin $ValidIntervals) {
                    throw "Invalid check interval: $CheckInterval. Valid: $($ValidIntervals -join ', ')"
                }
                if ($CheckTime -and ($CheckTime -lt 0 -or $CheckTime -gt 23)) {
                    throw "Invalid check time: $CheckTime. Must be 0-23 (UTC hour)."
                }

                # Read existing settings to preserve check results
                $Existing = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                $Entity = @{
                    PartitionKey    = 'Settings'
                    RowKey          = 'UpdateConfig'
                    AutoUpdate      = [string]$AutoUpdate
                    CheckInterval   = [string]$CheckInterval
                    CheckTime       = [string]($CheckTime ?? '')
                    LastCheck       = [string]($Existing.LastCheck ?? '')
                    UpdateAvailable = [string]($Existing.UpdateAvailable ?? 'false')
                    RunningDigest   = [string]($Existing.RunningDigest ?? '')
                    RemoteDigest    = [string]($Existing.RemoteDigest ?? '')
                }
                Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null

                $IntervalLabel = if ($CheckInterval -eq '0') { 'disabled' } else { "every $CheckInterval" }
                $AutoLabel = if ($AutoUpdate) { 'auto-restart enabled' } else { 'manual restart' }
                $TimeLabel = if ($CheckTime -and $CheckInterval -ne '0') { " at ${CheckTime}:00 UTC" } else { '' }
                $Result = "Update settings saved. Check interval: ${IntervalLabel}${TimeLabel}, $AutoLabel."
                Write-LogMessage -API $APIName -headers $Headers -message $Result -sev Info
                $Body = @{ Results = $Result }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to save update settings: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        'UpdateChannel' {
            try {
                $NewChannel = $Request.Body.Channel
                if ([string]::IsNullOrWhiteSpace($NewChannel)) {
                    throw 'Channel is required'
                }
                if ($NewChannel -notin $ValidChannels) {
                    throw "Invalid channel: $NewChannel. Valid channels: $($ValidChannels -join ', ')"
                }

                $site = Get-ContainerSiteInfo
                if (-not ($site.Subscription -and $site.RGName -and $site.SiteName)) {
                    throw 'Could not determine Azure App Service details from environment'
                }

                $apiVersion = '2024-11-01'
                $getUri = "https://management.azure.com/subscriptions/$($site.Subscription)/resourceGroups/$($site.RGName)/providers/Microsoft.Web/sites/$($site.SiteName)/config/web?api-version=$apiVersion"
                $webConfig = New-CIPPAzRestRequest -Uri $getUri -Method GET
                $currentLinuxFx = $webConfig.properties.linuxFxVersion
                if (-not $currentLinuxFx) {
                    throw 'Could not read current linuxFxVersion — is this a Linux container app?'
                }

                $currentImage = $currentLinuxFx -replace '^DOCKER\|', ''
                if ($currentImage -match '^(.+):([^:]+)$') {
                    $imageBase = $Matches[1]
                    $newLinuxFx = "DOCKER|${imageBase}:${NewChannel}"
                } else {
                    $newLinuxFx = "DOCKER|${currentImage}:${NewChannel}"
                }

                $putBody = @{ properties = @{ linuxFxVersion = $newLinuxFx } }
                New-CIPPAzRestRequest -Uri $getUri -Method PATCH -Body $putBody -ContentType 'application/json' | Out-Null

                $Result = "Release channel updated to '$NewChannel'. Image: $newLinuxFx. The container will pull the new image on next restart."
                Write-LogMessage -API $APIName -headers $Headers -message "Release channel changed to $NewChannel ($newLinuxFx)" -sev Info
                $Body = @{ Results = $Result }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to update channel: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        'Restart' {
            try {
                Write-LogMessage -API $APIName -headers $Headers -message 'Container restart requested by super admin' -sev Info
                $Body = @{ Results = 'Container restart initiated. The application will be back online shortly.' }
                try {
                    [Craft.Services.AppLifecycleBridge]::RequestRestart('Restart requested by super admin via container management page')
                } catch {
                    $Body = @{ Results = 'Restart command sent but the bridge is not available. The app may need to be restarted from the Azure Portal.' }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to restart: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
                }
            }
        }
        default {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Unknown action: $Action. Valid actions: Status, CheckUpdate, SaveUpdateSettings, UpdateChannel, Restart" }
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
