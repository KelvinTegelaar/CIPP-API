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

    switch ($Action) {
        'Status' {
            try {
                $CurrentVersion = $env:APP_VERSION ?? 'unknown'
                $CommitSha = $env:COMMIT_SHA ?? 'unknown'
                $ImageTag = $env:IMAGE_TAG ?? 'unknown'

                # The channel is the image tag baked into the container at build time
                $CurrentChannel = $ImageTag

                # Try to read the full container image reference from ARM
                $CurrentImage = 'unknown'
                $Subscription = Get-CIPPAzFunctionAppSubId
                $RGName = $env:WEBSITE_RESOURCE_GROUP
                if (-not $RGName) {
                    $Owner = $env:WEBSITE_OWNER_NAME
                    if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                        $RGName = $Matches.RGName
                    }
                }
                $SiteName = $env:WEBSITE_SITE_NAME
                if ($Subscription -and $RGName -and $SiteName) {
                    try {
                        $apiVersion = '2024-11-01'
                        $uri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/config/web?api-version=$apiVersion"
                        $webConfig = New-CIPPAzRestRequest -Uri $uri -Method GET
                        $linuxFxVersion = $webConfig.properties.linuxFxVersion
                        if ($linuxFxVersion) {
                            $CurrentImage = $linuxFxVersion -replace '^DOCKER\|', ''
                            # The ARM config tag may differ from the running container's baked-in tag
                            # if the channel was changed but the container hasn't restarted yet
                            if ($CurrentImage -match ':([^:]+)$') {
                                $ConfiguredChannel = $Matches[1]
                            }
                        }
                    } catch {
                        Write-Information "Could not read container config from ARM: $_"
                    }
                }

                $Body = @{
                    Results = @{
                        CurrentVersion    = $CurrentVersion
                        CommitSha         = $CommitSha
                        ImageTag          = $ImageTag
                        CurrentChannel    = $CurrentChannel
                        ConfiguredChannel = $ConfiguredChannel ?? $CurrentChannel
                        CurrentImage      = $CurrentImage
                        SiteName          = $SiteName
                        ValidChannels     = $ValidChannels
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
        'UpdateChannel' {
            try {
                $NewChannel = $Request.Body.Channel
                if ([string]::IsNullOrWhiteSpace($NewChannel)) {
                    throw 'Channel is required'
                }
                if ($NewChannel -notin $ValidChannels) {
                    throw "Invalid channel: $NewChannel. Valid channels: $($ValidChannels -join ', ')"
                }

                $Subscription = Get-CIPPAzFunctionAppSubId
                $RGName = $env:WEBSITE_RESOURCE_GROUP
                if (-not $RGName) {
                    $Owner = $env:WEBSITE_OWNER_NAME
                    if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                        $RGName = $Matches.RGName
                    }
                }
                $SiteName = $env:WEBSITE_SITE_NAME
                if (-not ($Subscription -and $RGName -and $SiteName)) {
                    throw 'Could not determine Azure App Service details from environment'
                }

                $apiVersion = '2024-11-01'

                # Read current web config
                $getUri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/config/web?api-version=$apiVersion"
                $webConfig = New-CIPPAzRestRequest -Uri $getUri -Method GET
                $currentLinuxFx = $webConfig.properties.linuxFxVersion
                if (-not $currentLinuxFx) {
                    throw 'Could not read current linuxFxVersion — is this a Linux container app?'
                }

                # Replace the tag in the image reference
                $currentImage = $currentLinuxFx -replace '^DOCKER\|', ''
                if ($currentImage -match '^(.+):([^:]+)$') {
                    $imageBase = $Matches[1]
                    $newLinuxFx = "DOCKER|${imageBase}:${NewChannel}"
                } else {
                    $newLinuxFx = "DOCKER|${currentImage}:${NewChannel}"
                }

                # Update the web config with new image tag
                $putUri = $getUri
                $putBody = @{
                    properties = @{
                        linuxFxVersion = $newLinuxFx
                    }
                }
                New-CIPPAzRestRequest -Uri $putUri -Method PATCH -Body $putBody -ContentType 'application/json' | Out-Null

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

                # Schedule restart after response is sent
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
                Body       = @{ Results = "Unknown action: $Action. Valid actions: Status, UpdateChannel, Restart" }
            }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
