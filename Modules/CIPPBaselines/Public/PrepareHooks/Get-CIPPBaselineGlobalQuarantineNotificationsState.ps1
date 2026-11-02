function Get-CIPPBaselineGlobalQuarantineNotificationsState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalQuarantineNotifications: the end-user notification interval.
    .DESCRIPTION
        The tenant stores the frequency as an ISO duration (PT4H/P1D/P7D) while the operator
        picks a .NET timespan string - both sides normalize to hours so the compare is a
        number, not two spellings of the same duration. An interval the tenant reports in
        any other shape grades as -1: unknown is drift, and remediation writes the wanted
        value.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoGlobalQuarantinePolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $Wanted = "$($Item.Variables.NotificationInterval.value ?? $Item.Variables.NotificationInterval)"
    $WantedHours = try { [int]([timespan]$Wanted).TotalHours } catch { return @{ Current = $null } }

    $CurrentHours = switch ("$($Policy.EndUserSpamNotificationFrequency)") {
        'PT4H' { 4 }
        'P1D' { 24 }
        'P7D' { 168 }
        default { -1 }
    }

    $Current = [PSCustomObject]@{ notificationIntervalHours = [int]$CurrentHours }
    $Current | Add-Member -NotePropertyName 'policyName' -NotePropertyValue "$($Policy.Name)"
    $Current | Add-Member -NotePropertyName 'policyIdentity' -NotePropertyValue "$($Policy.Identity)"

    @{
        Expected = [PSCustomObject]@{ notificationIntervalHours = [int]$WantedHours }
        Current  = $Current
    }
}
