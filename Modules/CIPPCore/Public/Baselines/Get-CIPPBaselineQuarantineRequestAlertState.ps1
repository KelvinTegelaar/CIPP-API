function Get-CIPPBaselineQuarantineRequestAlertState {
    <#
    .SYNOPSIS
        Prepare hook for QuarantineRequestAlert, in either of its two modes.
    .DESCRIPTION
        The 'Allow extra addresses' switch decides what correct means, so it decides the shape
        of the comparison too:

          on  - the configured address must be ON the notify list, and anything else there is
                somebody's deliberate addition. Graded as a single boolean, because an array
                compare can only demand the lists match. This is what the classic standard did.
          off - the notify list must be exactly the configured address. Graded as the list
                itself, so the drift row names the recipients that should not be there.

        Absence of the alert is DRIFT, not No Data: the classic standard treated a missing
        alert as incorrect and remediation creates it. Only an ExoProtectionAlert cache that
        has never been collected is genuinely unknown.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $PolicyName = 'CIPP User requested to release a quarantined message'
    $Configured = "$($Item.Variables.NotifyUser)"
    $AllowExtra = "$($Item.Variables.AllowExtraAddresses)" -notin @('False', 'false', '0')

    $Alerts = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoProtectionAlert' | Where-Object { $_ })
    if ($Alerts.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoProtectionAlert')) {
        return @{ Current = $null }
    }

    $Alert = @($Alerts | Where-Object { $_.Name -eq $PolicyName }) | Select-Object -First 1
    $Recipients = @(@($Alert.NotifyUser) | Where-Object { $_ })

    if ($AllowExtra) {
        return @{
            Expected = [PSCustomObject]@{ NotifyUserPresent = $true }
            Current  = [PSCustomObject]@{ NotifyUserPresent = [bool]($Recipients -contains $Configured) }
        }
    }

    @{
        Expected = [PSCustomObject]@{ NotifyUser = @($Configured) }
        Current  = [PSCustomObject]@{ NotifyUser = @($Recipients | Sort-Object) }
    }
}
