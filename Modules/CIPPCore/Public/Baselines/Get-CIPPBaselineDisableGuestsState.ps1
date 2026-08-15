function Get-CIPPBaselineDisableGuestsState {
    <#
    .SYNOPSIS
        Prepare hook for DisableGuests: enabled guests that are stale or never accepted their
        invitation.
    .DESCRIPTION
        Read live rather than from the Guests cache: that collector expands sponsors but
        selects neither signInActivity nor externalUserState, and both decide the verdict here.
        Extending it would let this move to cache like the other user sweeps.

        A guest counts when it has not signed in within the window, OR when it is still
        PendingAcceptance - an invitation nobody ever took up is exactly the account this is
        meant to close. Accounts an admin re-enabled in the last 7 days are left alone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $CheckDays = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.days)")) { 90 } else { [int]$Item.Variables.days }
    $Cutoff = (Get-Date).AddDays(-$CheckDays).ToUniversalTime()
    $Lookup = $Cutoff.ToString('o')

    $Guests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Guest' and accountEnabled eq true&`$select=id,userPrincipalName,signInActivity,mail,userType,accountEnabled,createdDateTime,externalUserState" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter)

    $Stale = @($Guests | Where-Object {
            if ($_.signInActivity -and $_.signInActivity.lastSuccessfulSignInDateTime) {
                ([datetime]$_.signInActivity.lastSuccessfulSignInDateTime).ToUniversalTime() -le $Cutoff
            } else {
                $_.externalUserState -eq 'PendingAcceptance'
            }
        })

    if ($Stale.Count -gt 0) {
        $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        $Reactivated = @(try {
                $Audits = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup&`$select=targetResources" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter
                @($Audits | ForEach-Object { $_.targetResources[0].id }) | Select-Object -Unique
            } catch {
                Write-Information "Baselines: reactivation audit lookup on $TenantFilter failed: $($_.Exception.Message)"
                @()
            })
        $Stale = @($Stale | Where-Object { $Reactivated -notcontains $_.id })
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Stale | ForEach-Object { "$($_.userPrincipalName ?? $_.mail)" } | Sort-Object)
            targets   = @($Stale | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
