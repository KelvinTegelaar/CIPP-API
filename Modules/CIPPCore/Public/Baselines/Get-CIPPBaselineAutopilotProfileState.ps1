function Get-CIPPBaselineAutopilotProfileState {
    <#
    .SYNOPSIS
        Prepare hook for AutopilotProfile: one named Windows Autopilot deployment profile.
    .DESCRIPTION
        Finds the configured profile by display name in the Autopilot profiles cache and
        grades the classic's exact field set. Two classic derivations are load-bearing:
        self-deploying mode forces White Glove OFF (the classic mutated the setting before
        comparing), and userType only grades outside shared mode. Locale grades
        empty-matches-empty, so a baseline with no language never drifts a profile without
        one.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Profiles = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneWindowsAutopilotDeploymentProfiles')
    if ($Profiles.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneWindowsAutopilotDeploymentProfiles')) {
        return @{ Current = $null }
    }

    $V = $Item.Variables
    # The identity may arrive as an option object ({label, value}) from some save paths -
    # unwrap before interpolating or the profile title becomes the stringified object.
    $DisplayName = "$($V.DisplayName.value ?? $V.DisplayName)"
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return @{ Current = $null } }
    $Profile = @($Profiles | Where-Object { "$($_.displayName)" -eq $DisplayName }) | Select-Object -First 1

    $UserType = $(if ($V.NotLocalAdmin -eq $true) { 'standard' } else { 'administrator' })
    $SelfDeploying = $V.SelfDeployingMode -eq $true
    $DeploymentMode = $(if ($SelfDeploying) { 'shared' } else { 'singleUser' })
    # Self-deploying mode cannot pre-provision - the classic forced White Glove off with it.
    $AllowWhiteGlove = $(if ($SelfDeploying) { $false } else { [bool]$V.AllowWhiteGlove })
    $Locale = "$($V.Languages.value ?? $V.Languages)"

    $Expected = [PSCustomObject]@{
        profileExists                 = $true
        displayName                   = $DisplayName
        description                   = "$($V.Description)"
        deviceNameTemplate            = "$($V.DeviceNameTemplate)"
        locale                        = $Locale
        preprovisioningAllowed        = $AllowWhiteGlove
        hardwareHashExtractionEnabled = [bool]$V.CollectHash
        deviceUsageType               = $DeploymentMode
        privacySettingsHidden         = [bool]$V.HidePrivacy
        eulaHidden                    = [bool]$V.HideTerms
        keyboardSelectionPageSkipped  = [bool]$V.AutoKeyboard
    }
    $Current = [PSCustomObject]@{
        profileExists                 = ($null -ne $Profile)
        displayName                   = "$($Profile.displayName)"
        description                   = "$($Profile.description)"
        deviceNameTemplate            = "$($Profile.deviceNameTemplate)"
        locale                        = $(if ($Locale -in @('', 'os-default') -and "$($Profile.locale)" -in @('', 'os-default')) { $Locale } else { "$($Profile.locale)" })
        preprovisioningAllowed        = [bool]$Profile.preprovisioningAllowed
        hardwareHashExtractionEnabled = [bool]$Profile.hardwareHashExtractionEnabled
        deviceUsageType               = "$($Profile.outOfBoxExperienceSetting.deviceUsageType)"
        privacySettingsHidden         = [bool]$Profile.outOfBoxExperienceSetting.privacySettingsHidden
        eulaHidden                    = [bool]$Profile.outOfBoxExperienceSetting.eulaHidden
        keyboardSelectionPageSkipped  = [bool]$Profile.outOfBoxExperienceSetting.keyboardSelectionPageSkipped
    }
    # userType only grades outside shared mode - shared profiles carry no meaningful value.
    if ($DeploymentMode -ne 'shared') {
        $Expected | Add-Member -NotePropertyName 'userType' -NotePropertyValue $UserType
        $Current | Add-Member -NotePropertyName 'userType' -NotePropertyValue "$($Profile.outOfBoxExperienceSetting.userType)"
    }

    @{ Expected = $Expected; Current = $Current }
}
