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

    # Throwaway images built from an unmerged branch by .github/workflows/preview-container.yml,
    # tagged <branch-type>-<name> (optionally + '-<shortsha>' for a pinned build). The type list
    # must stay in sync with that workflow and with preview-cleanup.yml. Nothing here can match
    # 'latest', 'dev', 'nightly' or a bare semver, so a build tag can never shadow a real channel.
    $BuildChannelPattern = '^(preview|feat|fix|refactor|perf|chore|build|revert)-[a-z0-9][a-z0-9._-]{0,54}$'

    # Used only to LIST available tags when ARM cannot tell us what image is deployed — local
    # development has no WEBSITE_SITE_NAME or managed identity, so the ARM lookup returns nothing
    # and the picker would otherwise show no branch builds at all. Switching channels still
    # derives its image base from the site's own linuxFxVersion, never from this.
    $DefaultImageBase = 'ghcr.io/cyberdrain/cipp'

    $SettingsTable = Get-CippTable -tablename 'ContainerUpdateSettings'

    # Helper: resolve ARM site details
    function Get-ContainerSiteInfo {
        $SiteName = $env:WEBSITE_SITE_NAME
        try {
            $RGName = Get-CIPPFunctionAppResourceGroup -SiteName $SiteName
        } catch {
            Write-Information "Could not determine resource group: $($_.Exception.Message)"
            $RGName = $null
        }
        return @{
            Subscription = Get-CIPPAzFunctionAppSubId
            SiteName     = $SiteName
            RGName       = $RGName
        }
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
        $created = $manifest.annotations.'org.opencontainers.image.created'
        if ((-not $version -or -not $created) -and $manifest.config.digest) {
            try {
                $config = Invoke-RestMethod -Uri "https://ghcr.io/v2/$imagePath/blobs/$($manifest.config.digest)" -Method GET -Headers $authHeader -ErrorAction Stop
                if (-not $version) { $version = $config.config.Labels.'org.opencontainers.image.version' }
                if (-not $created) { $created = $config.config.Labels.'org.opencontainers.image.created' }
            } catch {
                Write-Information "Could not read image config labels for $($imagePath):$Tag — $($_.Exception.Message)"
            }
        }

        return [pscustomobject]@{
            Digest  = [string]$digest
            Version = [string]$version
            Created = [string]$created
        }
    }

    # List the build-channel tags that actually exist on the registry, so the UI can offer a
    # pick-list instead of asking an admin to type a tag from memory. A typo'd tag would leave
    # linuxFxVersion pointing at a nonexistent image and the instance unable to start.
    # Anonymous pull token, same as Get-GHCRImageInfo.
    function Get-GHCRBuildChannel {
        param([string]$ImageRef)

        $imagePath = $ImageRef -replace '^ghcr\.io/', '' -replace ':.*$', ''
        if (-not $imagePath) { return @() }

        $tokenResp = Invoke-RestMethod -Uri "https://ghcr.io/token?scope=repository:${imagePath}:pull" -Method GET -ErrorAction Stop
        $authHeader = @{ Authorization = "Bearer $($tokenResp.token)" }

        $Tags = [System.Collections.Generic.List[string]]::new()
        $Uri = "https://ghcr.io/v2/$imagePath/tags/list?n=100"
        # GHCR paginates via a Link header; cap the walk so a huge tag list can't stall the page.
        for ($Page = 0; $Page -lt 20 -and $Uri; $Page++) {
            $Resp = Invoke-WebRequest -Uri $Uri -Method GET -Headers $authHeader -ErrorAction Stop
            $Content = $Resp.Content
            if ($Content -is [byte[]]) { $Content = [System.Text.Encoding]::UTF8.GetString($Content) }
            ($Content | ConvertFrom-Json).tags | ForEach-Object { $Tags.Add($_) }

            $Uri = $null
            $Link = $Resp.Headers['Link']
            if ($Link) {
                if ($Link -is [array]) { $Link = $Link[0] }
                if ($Link -match '<([^>]+)>\s*;\s*rel="next"') { $Uri = "https://ghcr.io$($Matches[1])" }
            }
        }

        return @($Tags | Where-Object { $_ -match $BuildChannelPattern } | Sort-Object)
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

                # Read update settings and last check result, reconciled against the running
                # build — a restart may have applied the previously detected update, which
                # would otherwise keep showing "update available" until the next check.
                # Sync also resolves defaults for never-saved fields (auto-restart on,
                # hourly checks, preferred time 23:00).
                $Settings = Sync-CippContainerUpdateState
                $UpdateInfo = @{
                    AutoUpdate      = $true
                    CheckInterval   = '1h'
                    CheckTime       = '23'
                    LastCheck       = $null
                    UpdateAvailable = $false
                    RunningVersion  = $null
                    RemoteVersion   = $null
                    RemoteDigest    = $null
                    RemoteBuildDate = $null
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
                    $UpdateInfo.RemoteBuildDate = $Settings.RemoteBuildDate ?? $null
                }

                # Note: the branch-build tag list is NOT fetched here. Status is polled, and each
                # call would hit the registry. The channel picker loads it from ListChannels
                # instead, which it can also re-fetch on demand.
                $Body = @{
                    Results = @{
                        CurrentVersion      = $CurrentVersion
                        CommitSha           = $CommitSha
                        ImageTag            = $ImageTag
                        BuildDate           = $env:BUILD_DATE ?? 'unknown'
                        CurrentChannel      = $CurrentChannel
                        ConfiguredChannel   = $ConfiguredChannel
                        CurrentImage        = $CurrentImage
                        SiteName            = $site.SiteName
                        ValidChannels       = $ValidChannels
                        BuildChannelPattern = $BuildChannelPattern
                        UpdateSettings      = $UpdateInfo
                        UpgradeHistory      = @(Get-CIPPVersionHistory -Last 50)
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
        'ListChannels' {
            # Selectable channels for the picker: the standard three, plus whatever branch builds
            # currently exist on the registry. Its own action rather than part of Status so the UI
            # can refresh it on demand (a branch build pushed a minute ago shows up immediately)
            # without the polled status call hitting the registry every time.
            try {
                $Channels = [System.Collections.Generic.List[object]]::new()
                foreach ($Channel in $ValidChannels) {
                    $Channels.Add([PSCustomObject]@{
                            label = $Channel
                            value = $Channel
                            group = 'Standard channels'
                        })
                }

                # Prefer the image actually deployed here, so a fork or a privately hosted image
                # lists its own tags. ARM is unavailable in local development (no
                # WEBSITE_SITE_NAME, no managed identity), so fall back to the published image
                # rather than silently listing no branch builds at all.
                $CurrentImage = $null
                $site = Get-ContainerSiteInfo
                if ($site.Subscription -and $site.RGName -and $site.SiteName) {
                    try {
                        $apiVersion = '2024-11-01'
                        $uri = "https://management.azure.com/subscriptions/$($site.Subscription)/resourceGroups/$($site.RGName)/providers/Microsoft.Web/sites/$($site.SiteName)/config/web?api-version=$apiVersion"
                        $webConfig = New-CIPPAzRestRequest -Uri $uri -Method GET
                        if ($webConfig.properties.linuxFxVersion) {
                            $CurrentImage = $webConfig.properties.linuxFxVersion -replace '^DOCKER\|', ''
                        }
                    } catch {
                        Write-Information "Could not read container config from ARM: $($_.Exception.Message)"
                    }
                }
                if (-not $CurrentImage) {
                    $CurrentImage = $DefaultImageBase
                    Write-Information "[Channels] No image reference from ARM, listing tags for $DefaultImageBase"
                }

                # An empty branch-build list must be distinguishable from a failed lookup - the
                # standard channels rendering fine otherwise makes a silent failure look like
                # "there are no branch builds", which is exactly what it is not.
                if ($CurrentImage -match '^ghcr\.io/') {
                    try {
                        $BuildTags = @(Get-GHCRBuildChannel -ImageRef $CurrentImage)
                        Write-Information "[Channels] Found $($BuildTags.Count) branch build tag(s) on $CurrentImage"
                        foreach ($Tag in $BuildTags) {
                            $Channels.Add([PSCustomObject]@{
                                    label = $Tag
                                    value = $Tag
                                    group = 'Branch builds'
                                })
                        }
                    } catch {
                        Write-LogMessage -API $APIName -headers $Headers -message "Could not list branch build tags from $($CurrentImage): $($_.Exception.Message)" -sev Warning
                    }
                } else {
                    Write-Information "[Channels] $CurrentImage is not a GHCR image - branch builds are not listed"
                }

                $Body = @{ Results = @($Channels) }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -headers $Headers -message "Failed to list channels: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
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
                    $Body = @{ Results = "Update checking is only supported for GHCR-hosted images. Current image: $CurrentImage" }
                    break
                }

                # Determine the channel tag to check (parsed from the configured image ref)
                $CheckTag = if ($CurrentImage -match ':([^:]+)$') { $Matches[1] } else { $ImageTag }

                # Query GHCR for the channel tag's manifest — gives us both the digest and
                # the version label that the CI baked in (org.opencontainers.image.version).
                $RemoteInfo = Get-GHCRImageInfo -ImageRef $CurrentImage -Tag $CheckTag
                $RemoteVersion = $RemoteInfo.Version
                $RemoteDigest = $RemoteInfo.Digest
                $RemoteBuildDate = $RemoteInfo.Created

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
                    RemoteBuildDate = [string]($RemoteBuildDate ?? '')
                    CheckedTag      = [string]($CheckTag ?? '')
                }
                $Existing = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                if ($Existing) {
                    # Carry saved schedule fields forward; never-saved fields materialize
                    # the defaults (auto-restart on, hourly, 23:00). An empty CheckTime is
                    # an explicit "no preferred time" and is preserved.
                    $Entity.AutoUpdate = $Existing.AutoUpdate ?? 'true'
                    $Entity.CheckInterval = $Existing.CheckInterval ?? '1h'
                    $Entity.CheckTime = $Existing.CheckTime ?? '23'
                }
                Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null

                $Settings = Sync-CippContainerUpdateState
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
                # Structured update state is persisted to UpdateConfig and surfaced via the
                # Status action; the POST response only carries the human-readable outcome.
                $Body = @{ Results = $Result }
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
                # CheckTime arrives as a string — validate as [int]. A string comparison
                # makes '3' -gt 23 true ('3' > '2' lexicographically), rejecting 03:00-09:00.
                if ($null -ne $CheckTime -and "$CheckTime" -ne '') {
                    $ParsedHour = 0
                    if (-not [int]::TryParse([string]$CheckTime, [ref]$ParsedHour) -or $ParsedHour -lt 0 -or $ParsedHour -gt 23) {
                        throw "Invalid check time: $CheckTime. Must be an hour between 0 and 23."
                    }
                    $CheckTime = $ParsedHour
                } else {
                    $CheckTime = $null
                }

                # Read existing settings to preserve check results — the upsert replaces the
                # whole entity, so every check-result field must be carried over here.
                $Existing = Get-CIPPAzDataTableEntity @SettingsTable -Filter "PartitionKey eq 'Settings' and RowKey eq 'UpdateConfig'" | Select-Object -First 1
                $Entity = @{
                    PartitionKey    = 'Settings'
                    RowKey          = 'UpdateConfig'
                    AutoUpdate      = [string]$AutoUpdate
                    CheckInterval   = [string]$CheckInterval
                    CheckTime       = [string]($CheckTime ?? '')
                    LastCheck       = [string]($Existing.LastCheck ?? '')
                    UpdateAvailable = [string]($Existing.UpdateAvailable ?? 'false')
                    RunningVersion  = [string]($Existing.RunningVersion ?? '')
                    RemoteVersion   = [string]($Existing.RemoteVersion ?? '')
                    RemoteDigest    = [string]($Existing.RemoteDigest ?? '')
                    RemoteBuildDate = [string]($Existing.RemoteBuildDate ?? '')
                    CheckedTag      = [string]($Existing.CheckedTag ?? '')
                }
                Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null

                $IntervalLabel = if ($CheckInterval -eq '0') { 'disabled' } else { "every $CheckInterval" }
                $AutoLabel = if ($AutoUpdate) { 'auto-restart enabled' } else { 'manual restart' }
                $TimeLabel = if ($null -ne $CheckTime -and $CheckInterval -ne '0') { " at $('{0:d2}' -f $CheckTime):00" } else { '' }
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
                $IsBuildChannel = $NewChannel -notin $ValidChannels -and $NewChannel -match $BuildChannelPattern
                if ($NewChannel -notin $ValidChannels -and -not $IsBuildChannel) {
                    throw "Invalid channel: $NewChannel. Valid channels: $($ValidChannels -join ', '), or a branch build tag."
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

                # Only ever the TAG is swapped — the image base comes from the site's existing
                # linuxFxVersion. That is what keeps this endpoint from being "point my instance
                # at any registry you like": a channel can only ever resolve to a tag on the
                # image already deployed here. Do not refactor into accepting a full image ref.
                $currentImage = $currentLinuxFx -replace '^DOCKER\|', ''
                if ($currentImage -match '^(.+):([^:]+)$') {
                    $imageBase = $Matches[1]
                } else {
                    $imageBase = $currentImage
                }
                $newLinuxFx = "DOCKER|${imageBase}:${NewChannel}"

                # A branch build tag is transient — the branch may have been deleted and the tag
                # swept. Writing a nonexistent image to linuxFxVersion takes the instance down on
                # next restart, so confirm the manifest resolves first. Built-in channels always
                # exist and keep their previous behaviour (no extra registry round-trip).
                if ($IsBuildChannel -and $imageBase -match '^ghcr\.io/') {
                    try {
                        $null = Get-GHCRImageInfo -ImageRef $imageBase -Tag $NewChannel
                    } catch {
                        throw "Branch build '$NewChannel' was not found in the registry — it may have been cleaned up after its branch was deleted. Pick another build, or rebuild the branch."
                    }
                }

                $putBody = @{ properties = @{ linuxFxVersion = $newLinuxFx } }
                New-CIPPAzRestRequest -Uri $getUri -Method PATCH -Body $putBody -ContentType 'application/json' | Out-Null

                if ($IsBuildChannel) {
                    $Result = "Release channel updated to branch build '$NewChannel'. Image: $newLinuxFx. The container will pull the new image on next restart. This is an unsupported build and will not receive updates — switch back to a standard channel when you are done testing."
                    Write-LogMessage -API $APIName -headers $Headers -message "Release channel changed to UNSUPPORTED branch build $NewChannel ($newLinuxFx)" -sev Warning
                } else {
                    $Result = "Release channel updated to '$NewChannel'. Image: $newLinuxFx. The container will pull the new image on next restart."
                    Write-LogMessage -API $APIName -headers $Headers -message "Release channel changed to $NewChannel ($newLinuxFx)" -sev Info
                }
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
