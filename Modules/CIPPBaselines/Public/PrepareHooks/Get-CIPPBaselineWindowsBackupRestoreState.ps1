function Get-CIPPBaselineWindowsBackupRestoreState {
    <#
    .SYNOPSIS
        Prepare hook for WindowsBackupRestore: the Windows Restore enrollment configuration.
    .DESCRIPTION
        Selected by deviceEnrollmentConfigurationType rather than by a fixed id, because the
        id carries the tenant's Intune account GUID. The row's id rides along on Current for
        the executor.
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

    $Config = @($Configurations | Where-Object { "$($_.deviceEnrollmentConfigurationType)" -eq 'windowsRestore' }) | Select-Object -First 1
    if (-not $Config) { return @{ Current = $null } }

    @{
        Expected = [PSCustomObject]@{ state = "$($Item.Variables.state)" }
        Current  = [PSCustomObject]@{
            state           = "$($Config.state)"
            configurationId = "$($Config.id)"
        }
    }
}
