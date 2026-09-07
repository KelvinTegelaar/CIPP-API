function Get-CIPPBaselineDisableGuestsState {
    <#
    .SYNOPSIS
        Prepare hook for DisableGuests: enabled guests with no sign-in attempt inside the window.
    .DESCRIPTION
        Read live rather than from the Guests cache: that collector expands sponsors but does not
        select signInActivity, which decides the verdict here. Extending it would let this move to
        cache like the other user sweeps.

        A guest counts when the newest of its interactive, non-interactive and successful sign-in
        timestamps is older than the window - the same view the Entra portal and the inactive-guest
        alert give. Guests with no sign-in on record (typically invitations nobody redeemed) only
        count when IncludeNeverSignedIn is on; it is off by default and off when the template
        predates it. Accounts an admin re-enabled in the last 7 days are left alone.
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
    $Cutoff = (Get-Date).AddDays(-$CheckDays).ToUniversalTime()
    $Lookup = $Cutoff.ToString('o')

    $Guests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=createdDateTime le $Lookup and userType eq 'Guest' and accountEnabled eq true&`$select=id,userPrincipalName,signInActivity,mail,userType,accountEnabled,createdDateTime" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter)

    $Stale = @($Guests | Where-Object {
            $LastSignIn = Get-CIPPLastSignInDateTime -SignInActivity $_.signInActivity
            if ($LastSignIn) { $LastSignIn -le $Cutoff } else { $IncludeNeverSignedIn }
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
