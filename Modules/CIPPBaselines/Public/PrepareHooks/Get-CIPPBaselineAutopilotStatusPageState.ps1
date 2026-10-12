function Get-CIPPBaselineAutopilotStatusPageState {
    <#
    .SYNOPSIS
        Prepare hook for AutopilotStatusPage: the default Enrollment Status Page.
    .DESCRIPTION
        Selected by type AND priority 0 - that pair identifies the default ESP, and any other
        priority is a targeted page somebody created deliberately.

        Two values are computed rather than read straight through, both carried verbatim from
        the classic standard:

        blockDeviceSetupRetryByUser is the INVERSE of the operator's 'Block device usage
        during setup' switch. A %token% cannot negate, which is why this is a hook.

        installQualityUpdates falls back to false when unset, preserving the v8.3.0
        back-compat default for baselines saved before that field existed.
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

    $Config = @($Configurations | Where-Object {
            "$($_.deviceEnrollmentConfigurationType)" -eq 'windows10EnrollmentCompletionPageConfiguration' -and
            [int]$_.priority -eq 0
        }) | Select-Object -First 1
    if (-not $Config) { return @{ Current = $null } }

    $V = $Item.Variables
    $Expected = [PSCustomObject]@{
        installProgressTimeoutInMinutes      = [int]"$($V.TimeOutInMinutes)"
        customErrorMessage                   = "$($V.ErrorMessage)"
        showInstallationProgress             = [bool]($V.ShowProgress -eq $true)
        allowLogCollectionOnInstallFailure   = [bool]($V.EnableLog -eq $true)
        trackInstallProgressForAutopilotOnly = [bool]($V.OBEEOnly -eq $true)
        blockDeviceSetupRetryByUser          = -not [bool]($V.BlockDevice -eq $true)
        installQualityUpdates                = [bool]($V.InstallWindowsUpdates -eq $true)
        allowDeviceResetOnInstallFailure     = [bool]($V.AllowReset -eq $true)
        allowDeviceUseOnInstallFailure       = [bool]($V.AllowFail -eq $true)
    }
    $Current = [PSCustomObject]@{
        installProgressTimeoutInMinutes      = $(if ($null -eq $Config.installProgressTimeoutInMinutes) { -1 } else { [int]$Config.installProgressTimeoutInMinutes })
        customErrorMessage                   = "$($Config.customErrorMessage)"
        showInstallationProgress             = [bool]$Config.showInstallationProgress
        allowLogCollectionOnInstallFailure   = [bool]$Config.allowLogCollectionOnInstallFailure
        trackInstallProgressForAutopilotOnly = [bool]$Config.trackInstallProgressForAutopilotOnly
        blockDeviceSetupRetryByUser          = [bool]$Config.blockDeviceSetupRetryByUser
        installQualityUpdates                = [bool]$Config.installQualityUpdates
        allowDeviceResetOnInstallFailure     = [bool]$Config.allowDeviceResetOnInstallFailure
        allowDeviceUseOnInstallFailure       = [bool]$Config.allowDeviceUseOnInstallFailure
        configurationId                      = "$($Config.id)"
        # Executor carrier like configurationId: the DESIRED retry-block value. It is
        # the inverse of the BlockDevice switch and a %token% cannot negate, so the
        # remediate body cannot render it - without this the write would fix every
        # property except the one, and that drift would flap forever.
        blockDeviceSetupRetryByUserDesired   = -not [bool]($V.BlockDevice -eq $true)
    }

    @{ Expected = $Expected; Current = $Current }
}
