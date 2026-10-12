function Get-CIPPBaselineEnrollmentWindowsHelloForBusinessConfigurationState {
    <#
    .SYNOPSIS
        Prepare hook for EnrollmentWindowsHelloForBusinessConfiguration: the default WHfB
        enrollment configuration.
    .DESCRIPTION
        The classic standard ordered by priority and took the first row - the default WHfB
        configuration - so the same ordering is applied here rather than trusting cache order.

        Two settings are graded only when the operator supplied them, matching the classic
        '($null -eq $Settings.X) -or ...' tests: enhancedSignInSecurity and securityKeyForSignIn
        are newer fields that older baselines will not carry, and grading them unset would
        report drift against a value the baseline never expressed an opinion on.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Configurations = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'DeviceEnrollmentConfigurations')
    if ($Configurations.Count -eq 0) { return @{ Current = $null } }

    $Config = @($Configurations |
            Where-Object { "$($_.deviceEnrollmentConfigurationType)" -eq 'windowsHelloForBusiness' } |
            Sort-Object -Property { [int]$_.priority }) | Select-Object -First 1
    if (-not $Config) { return @{ Current = $null } }

    $V = $Item.Variables
    $Expected = [PSCustomObject]@{
        pinMinimumLength            = [int]"$($V.pinMinimumLength)"
        pinMaximumLength            = [int]"$($V.pinMaximumLength)"
        pinUppercaseCharactersUsage = "$($V.pinUppercaseCharactersUsage)"
        pinLowercaseCharactersUsage = "$($V.pinLowercaseCharactersUsage)"
        pinSpecialCharactersUsage   = "$($V.pinSpecialCharactersUsage)"
        state                       = "$($V.state)"
        securityDeviceRequired      = [bool]($V.securityDeviceRequired -eq $true)
        unlockWithBiometricsEnabled = [bool]($V.unlockWithBiometricsEnabled -eq $true)
        remotePassportEnabled       = [bool]($V.remotePassportEnabled -eq $true)
        pinPreviousBlockCount       = [int]"$($V.pinPreviousBlockCount)"
        pinExpirationInDays         = [int]"$($V.pinExpirationInDays)"
        enhancedBiometricsState     = "$($V.enhancedBiometricsState)"
    }
    $Current = [PSCustomObject]@{
        pinMinimumLength            = $(if ($null -eq $Config.pinMinimumLength) { -1 } else { [int]$Config.pinMinimumLength })
        pinMaximumLength            = $(if ($null -eq $Config.pinMaximumLength) { -1 } else { [int]$Config.pinMaximumLength })
        pinUppercaseCharactersUsage = "$($Config.pinUppercaseCharactersUsage)"
        pinLowercaseCharactersUsage = "$($Config.pinLowercaseCharactersUsage)"
        pinSpecialCharactersUsage   = "$($Config.pinSpecialCharactersUsage)"
        state                       = "$($Config.state)"
        securityDeviceRequired      = [bool]$Config.securityDeviceRequired
        unlockWithBiometricsEnabled = [bool]$Config.unlockWithBiometricsEnabled
        remotePassportEnabled       = [bool]$Config.remotePassportEnabled
        pinPreviousBlockCount       = $(if ($null -eq $Config.pinPreviousBlockCount) { -1 } else { [int]$Config.pinPreviousBlockCount })
        pinExpirationInDays         = $(if ($null -eq $Config.pinExpirationInDays) { -1 } else { [int]$Config.pinExpirationInDays })
        enhancedBiometricsState     = "$($Config.enhancedBiometricsState)"
    }

    if (-not [string]::IsNullOrWhiteSpace("$($V.enhancedSignInSecurity)")) {
        $Expected | Add-Member -NotePropertyName 'enhancedSignInSecurity' -NotePropertyValue ([int]"$($V.enhancedSignInSecurity)")
        $Current | Add-Member -NotePropertyName 'enhancedSignInSecurity' -NotePropertyValue $(if ($null -eq $Config.enhancedSignInSecurity) { -1 } else { [int]$Config.enhancedSignInSecurity })
    }
    if (-not [string]::IsNullOrWhiteSpace("$($V.securityKeyForSignIn)")) {
        $Expected | Add-Member -NotePropertyName 'securityKeyForSignIn' -NotePropertyValue "$($V.securityKeyForSignIn)"
        $Current | Add-Member -NotePropertyName 'securityKeyForSignIn' -NotePropertyValue "$($Config.securityKeyForSignIn)"
    }

    $Current | Add-Member -NotePropertyName 'configurationId' -NotePropertyValue "$($Config.id)"

    @{ Expected = $Expected; Current = $Current }
}
