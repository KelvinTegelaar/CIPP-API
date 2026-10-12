function Get-CIPPBaselineDisableGuestsState {
    <#
    .SYNOPSIS
        Prepare hook for DisableGuests: stale guests to disable and (optionally) already-disabled guests to delete.
    .DESCRIPTION
        Read live rather than from the Guests cache: that collector expands sponsors but does not
        select signInActivity, which decides the verdict here. Extending it would let this move to
        cache like the other user sweeps.

        Produces TWO write sets, because the lifecycle is two-phase and deliberately so:
          guestsToDisable - stale and still enabled.
          guestsToDelete  - already disabled AND past disable+grace days (only when deleteGraceDays > 0).
        A guest is therefore never deleted in the same pass that disabled it; the disable is
        the warning shot, and an admin has the delete delta to notice and re-enable.

        A guest counts when the newest of its interactive, non-interactive and successful sign-in
        timestamps is older than the window - the same view the Entra portal and the inactive-guest
        alert give. Guests with no sign-in on record (typically invitations nobody redeemed) only
        count when IncludeNeverSignedIn is on; it is off by default and off when the template
        predates it. Accounts an admin re-enabled in the last 7 days are left alone on the disable set.
        Missing/blank/0 deleteGraceDays leaves guestsToDelete empty so existing templates stay disable-only.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $CheckDays = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.days)")) { 90 } else { [int]$Item.Variables.days }
    $IncludeNeverSignedIn = $Item.Variables.IncludeNeverSignedIn -eq $true
    $DeleteDelta = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.deleteGraceDays)")) { 0 } else { [int]$Item.Variables.deleteGraceDays }
    if ($DeleteDelta -lt 0) { $DeleteDelta = 0 }
    $DeleteEnabled = $DeleteDelta -gt 0
    $DeleteAge = $CheckDays + $DeleteDelta

    $Cutoff = (Get-Date).AddDays(-$CheckDays).ToUniversalTime()
    $Lookup = $Cutoff.ToString('o')
    $DeleteCutoff = (Get-Date).AddDays(-$DeleteAge).ToUniversalTime()
    $DeleteLookup = $DeleteCutoff.ToString('o')
    $GuestSelect = 'id,userPrincipalName,signInActivity,mail,userType,accountEnabled,createdDateTime'

    $TestStale = {
        param($Guest, $Window)
        $LastSignIn = Get-CIPPLastSignInDateTime -SignInActivity $Guest.signInActivity
        if ($LastSignIn) { $LastSignIn -le $Window } else { $IncludeNeverSignedIn }
    }

    $EnabledGuests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Guest' and accountEnabled eq true&`$select=$GuestSelect" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter)
    $ToDisable = @($EnabledGuests | Where-Object { & $TestStale $_ $Cutoff })

    if ($ToDisable.Count -gt 0) {
        $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        $Reactivated = @(try {
                $Audits = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup&`$select=targetResources" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter
                @($Audits | ForEach-Object { $_.targetResources[0].id }) | Select-Object -Unique
            } catch {
                Write-Information "Baselines: reactivation audit lookup on $TenantFilter failed: $($_.Exception.Message)"
                @()
            })
        $ToDisable = @($ToDisable | Where-Object { $Reactivated -notcontains $_.id })
    }

    $ToDelete = @(if ($DeleteEnabled) {
            $DisabledGuests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $DeleteLookup and userType eq 'Guest' and accountEnabled eq false&`$select=$GuestSelect" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter)
            $DisabledGuests | Where-Object { & $TestStale $_ $DeleteCutoff }
        })

    @{
        Current = [PSCustomObject]@{
            offenders        = @(@($ToDisable | ForEach-Object { "Disable: $($_.userPrincipalName ?? $_.mail)" }) + @($ToDelete | ForEach-Object { "Delete: $($_.userPrincipalName ?? $_.mail)" }) | Sort-Object)
            guestsToDisable  = @($ToDisable | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
            guestsToDelete   = @($ToDelete | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
