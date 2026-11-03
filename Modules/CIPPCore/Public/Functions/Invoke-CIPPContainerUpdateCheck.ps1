function Invoke-CIPPContainerUpdateCheck {
    <#
    .SYNOPSIS
        Checks the channel image for an update, verifies it, pins it and decides on a restart.
    .DESCRIPTION
        Shared by the update-check timer and the CheckUpdate/UpdateChannel actions. Writes the
        ContainerUpdateSettings UpdateConfig row and returns the outcome.

        Writing linuxFxVersion recycles the container, so the verified digest is only pinned where a
        restart is intended: an auto-update, the first pin of the running build (auto-restart on), or
        a channel switch. Failed or Unverifiable images never touch the pin.

        Status is 'NoImage' (no linuxFxVersion from ARM), 'NotGHCR', 'LookupFailed' or 'Checked'.
    .PARAMETER Settings
        Effective settings from Sync-CippContainerUpdateState; read when omitted.
    .PARAMETER Channel
        Switch the site to this tag: writes base:Channel@digest when it verifies, base:Channel otherwise.
        A failed registry lookup still writes base:Channel and returns Status 'LookupFailed'.
    .PARAMETER RequireTag
        Rethrow a failed registry lookup instead, so a missing tag is never written.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Invoke-CIPPContainerUpdateCheck -APIName 'ContainerUpdateCheck'
    #>
    [CmdletBinding()]
    param(
        $Settings,
        [string]$Channel,
        [switch]$RequireTag,
        [string]$APIName = 'ContainerUpdateCheck',
        $Headers
    )

    if (-not $Settings) { $Settings = Sync-CippContainerUpdateState }

    $Result = [pscustomobject]@{
        Status            = 'NoImage'
        Tag               = ''
        RunningVersion    = [string]($env:APP_VERSION ?? '')
        RemoteVersion     = ''
        RemoteDigest      = ''
        UpdateAvailable   = $false
        AttestationState  = ''
        AttestationReason = ''
        PinnedDigest      = ''
        PinChanged        = $false
        Restarted         = $false
        LinuxFxVersion    = ''
    }

    $Subscription = Get-CIPPAzFunctionAppSubId
    $SiteName = $env:WEBSITE_SITE_NAME
    try {
        $RGName = Get-CIPPFunctionAppResourceGroup -SiteName $SiteName
    } catch {
        Write-Information "Could not determine resource group: $($_.Exception.Message)"
        $RGName = $null
    }
    if (-not ($Subscription -and $RGName -and $SiteName)) { return $Result }

    $ConfigUri = "https://management.azure.com/subscriptions/$Subscription/resourceGroups/$RGName/providers/Microsoft.Web/sites/$SiteName/config/web?api-version=2024-11-01"
    $LinuxFx = (New-CIPPAzRestRequest -Uri $ConfigUri -Method GET).properties.linuxFxVersion
    if (-not $LinuxFx) { return $Result }

    $Image = ConvertFrom-CIPPContainerImageRef -Reference $LinuxFx
    $Tag = if ($Channel) { $Channel } elseif ($Image.Tag) { $Image.Tag } else { [string]($env:IMAGE_TAG ?? 'unknown') }
    $Result.Tag = $Tag
    $Result.PinnedDigest = $Image.Digest
    $Result.LinuxFxVersion = $LinuxFx

    # Only the tag and digest are ever written; Base always comes from the site's own linuxFxVersion,
    # so nothing here can point the instance at a different image or registry.
    function Set-ContainerImagePin([string]$Digest) {
        $Ref = if ($Digest) { "DOCKER|$($Image.Base):${Tag}@${Digest}" } else { "DOCKER|$($Image.Base):${Tag}" }
        New-CIPPAzRestRequest -Uri $ConfigUri -Method PATCH -Body @{ properties = @{ linuxFxVersion = $Ref } } -ContentType 'application/json' | Out-Null
        $Result.LinuxFxVersion = $Ref
        $Result.PinChanged = $Digest -ne $Result.PinnedDigest
        $Result.PinnedDigest = $Digest
    }

    if ($Image.Registry -ne 'ghcr.io') {
        $Result.Status = 'NotGHCR'
        if ($Channel) { Set-ContainerImagePin '' }
        return $Result
    }
    $Result.Status = 'Checked'

    $ImagePath = $Image.Base -replace '^ghcr\.io/', ''
    try {
        $Remote = Get-CIPPGHCRImageInfo -ImagePath $ImagePath -Tag $Tag
    } catch {
        if (-not $Channel -or $RequireTag) { throw }
        # A registry outage must not block switching to a standard channel; it just goes unpinned.
        Set-ContainerImagePin ''
        $Result.Status = 'LookupFailed'
        $Result.AttestationState = 'Unverifiable'
        $Result.AttestationReason = $_.Exception.Message
        $Remote = [pscustomobject]@{ Digest = ''; Version = ''; Created = ''; AuthHeader = $null }
    }
    $Result.RemoteVersion = $Remote.Version
    $Result.RemoteDigest = $Remote.Digest
    $RunningVersion = $Result.RunningVersion
    $UpdateAvailable = [bool]($Remote.Version -and $RunningVersion -and $Remote.Version -ne $RunningVersion)
    $Result.UpdateAvailable = $UpdateAvailable

    # Verified on every check so an up-to-date instance still shows whether its channel image is attested.
    $Attestation = [pscustomobject]@{ State = $Result.AttestationState; Reason = $Result.AttestationReason }
    if ($Remote.Digest) {
        $Attestation = Test-CIPPContainerAttestation -ImagePath $ImagePath -Digest $Remote.Digest -Tag $Tag -AuthHeader $Remote.AuthHeader
    }
    $Result.AttestationState = [string]$Attestation.State
    $Result.AttestationReason = [string]$Attestation.Reason
    $Verified = $Attestation.State -eq 'Verified'
    $AutoUpdate = $Settings.AutoUpdate -eq 'true'

    if ($Channel) {
        # A failed lookup already wrote the bare tag.
        if ($Result.Status -ne 'LookupFailed') { Set-ContainerImagePin $(if ($Verified) { $Remote.Digest } else { '' }) }
    } elseif ($Verified -and $AutoUpdate -and $UpdateAvailable) {
        Write-LogMessage -API $APIName -headers $Headers -message "Auto-update: new container version detected (running: $RunningVersion, remote: $($Remote.Version)). Restarting." -sev Info
        try {
            # The pin write is itself the restart; only an already-pinned digest needs an explicit one.
            if ($Remote.Digest -ne $Image.Digest) {
                Set-ContainerImagePin $Remote.Digest
            } else {
                Request-CIPPRestart -Reason 'Auto-update: new container version available'
            }
            $Result.Restarted = $true
        } catch {
            Write-LogMessage -API $APIName -headers $Headers -message "Auto-restart requested but could not be applied: $($_.Exception.Message)" -sev Warning
        }
    } elseif ($Verified -and $AutoUpdate -and -not $Image.Digest) {
        # First pin of the running build: one restart onto the same image.
        try {
            Set-ContainerImagePin $Remote.Digest
            Write-LogMessage -API $APIName -headers $Headers -message "Pinned the running container image to $($Remote.Digest)" -sev Info
        } catch {
            Write-Information "Could not pin the running container image: $($_.Exception.Message)"
        }
    }

    $SettingsTable = Get-CippTable -tablename 'ContainerUpdateSettings'
    $Entity = @{
        PartitionKey             = 'Settings'
        RowKey                   = 'UpdateConfig'
        AutoUpdate               = [string]($Settings.AutoUpdate ?? 'true')
        CheckInterval            = [string]($Settings.CheckInterval ?? '1h')
        CheckTime                = [string]($Settings.CheckTime ?? '23')
        LastCheck                = [string][int64](([DateTimeOffset]::UtcNow).ToUnixTimeSeconds())
        UpdateAvailable          = [string]$UpdateAvailable
        RunningVersion           = $RunningVersion
        RemoteVersion            = [string]$Remote.Version
        RemoteDigest             = [string]$Remote.Digest
        RemoteBuildDate          = [string]$Remote.Created
        CheckedTag               = [string]$Tag
        AttestationState         = $Result.AttestationState
        AttestationReason        = $Result.AttestationReason
        PinnedDigest             = [string]$Result.PinnedDigest
        RunningAttestationState  = [string]($Settings.RunningAttestationState ?? '')
        RunningAttestationReason = [string]($Settings.RunningAttestationReason ?? '')
        RunningDigest            = [string]($Settings.RunningDigest ?? '')
    }
    Add-CIPPAzDataTableEntity @SettingsTable -Entity $Entity -Force | Out-Null

    # Channel switches are logged by the caller; an auto-update was logged above.
    if ($Channel -or $Result.Restarted) {
        return $Result
    }
    if ($UpdateAvailable -and $Attestation.State -eq 'Failed') {
        Write-LogMessage -API $APIName -headers $Headers -message "Container update $($Remote.Version) failed provenance verification: $($Attestation.Reason). Auto-restart withheld." -sev Warning
    } elseif ($UpdateAvailable -and $Attestation.State -eq 'Unverifiable') {
        Write-Information "Container update $($Remote.Version) provenance could not be verified, retrying next check: $($Attestation.Reason)"
    } elseif ($UpdateAvailable) {
        Write-LogMessage -API $APIName -headers $Headers -message "Container update available (running: $RunningVersion, remote: $($Remote.Version))" -sev Info
    } elseif ($Attestation.State -in 'Failed', 'Unverifiable') {
        # Information only: channels whose current image predates attestation would otherwise warn every check.
        Write-Information "Container is up to date. Version: $RunningVersion. Channel image provenance $($Attestation.State): $($Attestation.Reason)"
    } else {
        Write-Information "Container is up to date. Version: $RunningVersion"
    }

    return $Result
}
