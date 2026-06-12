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

    # Helper: query GHCR for the image at $Tag and return its digest + version label.
    # The version label is set by the CI build (org.opencontainers.image.version) and matches
    # $env:APP_VERSION in the running container — comparing them tells us whether the channel
    # tag has been republished to a different build.
    function Get-GHCRImageInfo {
        param([string]$ImageRef, [string]$Tag)

        $imagePath = $ImageRef -replace '^ghcr\.io/', '' -replace ':.*$', ''
        if (-not $imagePath) { throw 'Could not parse image path from reference' }

        # PS7's Invoke-WebRequest returns .Content as byte[] when the response lacks a charset
        # (GHCR manifest media types omit it), so piping straight to ConvertFrom-Json yields
        # an int array. Decode bytes first.
        function ConvertFrom-RawJson($Content) {
            if ($Content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }
            return $Content | ConvertFrom-Json
        }

        $tokenResp = Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:${imagePath}:pull" -Method GET -ErrorAction Stop
        $authHeader = @{ Authorization = "Bearer $($tokenResp.token)" }
        $manifestAccept = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'

        $manifestUri = "https://ghcr.io/v2/$imagePath/manifests/$Tag"
        $manifestHeaders = $authHeader + @{ Accept = $manifestAccept }
        $resp = Invoke-WebRequest -Uri $manifestUri -Method GET -Headers $manifestHeaders -ErrorAction Stop
        $digest = $resp.Headers['Docker-Content-Digest']
        if ($digest -is [array]) { $digest = $digest[0] }
        $manifest = ConvertFrom-RawJson $resp.Content

        if ($manifest.manifests) {
            $child = $manifest.manifests | Where-Object { $_.platform.architecture -eq 'amd64' -and $_.platform.os -eq 'linux' } | Select-Object -First 1
            if (-not $child) { $child = $manifest.manifests | Select-Object -First 1 }
            $childResp = Invoke-WebRequest -Uri "https://ghcr.io/v2/$imagePath/manifests/$($child.digest)" -Method GET -Headers $manifestHeaders -ErrorAction Stop
            $manifest = ConvertFrom-RawJson $childResp.Content
        }

        $version = $manifest.annotations.'org.opencontainers.image.version'
        if (-not $version -and $manifest.config.digest) {
            try {
                $config = Invoke-RestMethod -Uri "https://ghcr.io/v2/$imagePath/blobs/$($manifest.config.digest)" -Method GET -Headers $authHeader -ErrorAction Stop
                $version = $config.config.Labels.'org.opencontainers.image.version'
            } catch {
                Write-Information "Could not read image config labels for $($imagePath):$Tag — $($_.Exception.Message)"
            }
        }

        return [pscustomobject]@{
            Digest  = [string]$digest
            Version = [string]$version
        }
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
                    AutoUpdate      = $false
                    CheckInterval   = '0'
                    CheckTime       = $null
                    LastCheck       = $null
                    UpdateAvailable = $false
                    RunningVersion  = $null
                    RemoteVersion   = $null
                    RemoteDigest    = $null
                }
                if ($Settings) {
                    $UpdateInfo.AutoUpdate = $Settings.AutoUpdate -eq 'true'
                    $UpdateInfo.CheckInterval = $Settings.CheckInterval ?? '0'
                    $UpdateInfo.CheckTime = $Settings.CheckTime ?? $null
                    $UpdateInfo.LastCheck = if ($Settings.LastCheck) { [int64]$Settings.LastCheck } else { $null }
                    $UpdateInfo.UpdateAvailable = $Settings.UpdateAvailable -eq 'true'
                    $UpdateInfo.RunningVersion = $Settings.RunningVersion ?? $null
                    $UpdateInfo.RemoteVersion = $Settings.RemoteVersion ?? $null
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

                # Determine the channel tag to check (parsed from the configured image ref)
                $CheckTag = if ($CurrentImage -match ':([^:]+)$') { $Matches[1] } else { $ImageTag }

                # Query GHCR for the channel tag's manifest — gives us both the digest and
                # the version label that the CI baked in (org.opencontainers.image.version).
                $RemoteInfo = Get-GHCRImageInfo -ImageRef $CurrentImage -Tag $CheckTag
                $RemoteVersion = $RemoteInfo.Version
                $RemoteDigest = $RemoteInfo.Digest

                $RunningVersion = $env:APP_VERSION
                $UpdateAvailable = $false
                if ($RemoteVersion -and $RunningVersion -and $RemoteVersion -ne $RunningVersion) {
                    $UpdateAvailable = $true
                }

                $Entity = @{
                    PartitionKey    = 'Settings'
                    RowKey          = 'UpdateConfig'
                    LastCheck       = [string][int64](([DateTimeOffset]::UtcNow).ToUnixTimeSeconds())
                    UpdateAvailable = [string]$UpdateAvailable
                    RunningVersion  = [string]($RunningVersion ?? '')
                    RemoteVersion   = [string]($RemoteVersion ?? '')
                    RemoteDigest    = [string]($RemoteDigest ?? '')
                }
                $Existing = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                if ($Existing) {
                    $Entity.AutoUpdate = $Existing.AutoUpdate ?? 'false'
                    $Entity.CheckInterval = $Existing.CheckInterval ?? '0'
                    $Entity.CheckTime = $Existing.CheckTime ?? ''
                }
                Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null

                $Settings = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                if ($UpdateAvailable -and $Settings.AutoUpdate -eq 'true') {
                    Write-LogMessage -API $APIName -headers $Headers -message "Auto-update: new container version detected (running: $RunningVersion, remote: $RemoteVersion). Restarting." -sev Info
                    try { Request-CIPPRestart -Reason 'Auto-update: new container version available' } catch {}
                    $Result = "Update available — container restart initiated (auto-update enabled). Running: $RunningVersion, Remote: $RemoteVersion"
                } elseif ($UpdateAvailable) {
                    $Result = "Update available. Running: $RunningVersion, Remote: $RemoteVersion. Restart the container to apply."
                    Write-LogMessage -API $APIName -headers $Headers -message "Container update available (running: $RunningVersion, remote: $RemoteVersion)" -sev Info
                } else {
                    $Result = "Container is up to date. Version: $RunningVersion"
                }
                $Body = @{
                    Results = @{
                        Message         = $Result
                        UpdateAvailable = $UpdateAvailable
                        RunningVersion  = $RunningVersion
                        RemoteVersion   = $RemoteVersion
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
                    Request-CIPPRestart -Reason 'Restart requested by super admin via container management page'
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
