function Get-CIPPBaselineStaleEntraDevicesState {
    <#
    .SYNOPSIS
        Prepare hook for StaleEntraDevices: device records past their last-seen thresholds.
    .DESCRIPTION
        Produces TWO write sets, because the lifecycle is two-phase and deliberately so:
          devicesToDisable - stale and still enabled.
          devicesToDelete  - already disabled AND past disable+delete days.
        A device is therefore never deleted in the same pass that disabled it; the disable is
        the warning shot, and an admin has the delete delta to notice and re-enable.

        The safety filter is not optional: a device that is directory-synced, Intune-managed,
        compliant, or carries a ZTDID (Autopilot-registered) is excluded regardless of age.
        Those records are owned elsewhere and deleting one breaks enrolment.

        A disable threshold under 30 days is refused rather than clamped, matching the classic
        standard - the delete phase makes a low value unrecoverable.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $DisableThreshold = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.deviceAgeThreshold)")) { 0 } else { [int]$Item.Variables.deviceAgeThreshold }
    if ($DisableThreshold -lt 30) { throw "StaleEntraDevices: a disable threshold of $DisableThreshold days is below the 30-day floor - refusing to run." }

    $DeleteDelta = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.deviceDeleteThreshold)")) { 0 } else { [int]$Item.Variables.deviceDeleteThreshold }
    if ($DeleteDelta -lt 0) { $DeleteDelta = 0 }

    $Devices = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Devices' | Where-Object { $_ -and $_.approximateLastSignInDateTime })
    if ($Devices.Count -eq 0) {
        # A tenant with no registered devices - or none that ever signed in - has nothing
        # stale to clean up. Once the type has been collected that is compliant, not unknown.
        if (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Devices') {
            return @{ Current = [PSCustomObject]@{ offenders = @(); devicesToDisable = @(); devicesToDelete = @() } }
        }
        return @{ Current = $null }
    }

    $DisableDate = (Get-Date).AddDays(-$DisableThreshold)
    $DeleteDate = (Get-Date).AddDays(-($DisableThreshold + $DeleteDelta))

    $Safe = {
        $_.onPremisesSyncEnabled -ne $true -and
        $_.isManaged -ne $true -and
        $_.isCompliant -ne $true -and
        (@($_.physicalIds) -join ' ') -notmatch '\[ZTDID\]'
    }

    $ToDisable = @($Devices | Where-Object { ([datetime]$_.approximateLastSignInDateTime) -lt $DisableDate } | Where-Object $Safe | Where-Object { $_.accountEnabled -eq $true })
    $ToDelete = @(if ($DeleteDelta -gt 0) {
            $Devices | Where-Object { ([datetime]$_.approximateLastSignInDateTime) -lt $DeleteDate } | Where-Object $Safe | Where-Object { $_.accountEnabled -ne $true }
        })

    @{
        Current = [PSCustomObject]@{
            offenders       = @(@($ToDisable | ForEach-Object { "Disable: $($_.displayName)" }) + @($ToDelete | ForEach-Object { "Delete: $($_.displayName)" }) | Sort-Object)
            devicesToDisable = @($ToDisable | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
            devicesToDelete  = @($ToDelete | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
