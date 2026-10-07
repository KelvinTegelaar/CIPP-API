function Get-CIPPBaselineDisableInactiveUsersState {
    <#
    .SYNOPSIS
        Prepare hook for DisableInactiveUsers: enabled cloud-only members who have not signed
        in within the configured window.
    .DESCRIPTION
        Cache-backed except for one live query. The Users cache carries createdDateTime and,
        on tenants licensed for sign-in logs, signInActivity - a tenant without that licence
        has no signInActivity at all, so no user can be judged inactive and the offender set
        is empty, exactly as the classic standard behaved.

        The live query is the reactivation grace period: an account an admin deliberately
        re-enabled in the last 7 days is left alone, otherwise the sweep would fight the
        admin every night. directoryAudits is not cached anywhere and is a single small read.

        A threshold under 30 days is refused rather than clamped - the classic standard
        aborted for the same reason, since a low value turns this into a mass account
        disablement.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $CheckDays = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.days)")) { 180 } else { [int]$Item.Variables.days }
    if ($CheckDays -lt 30) { throw "DisableInactiveUsers: a threshold of $CheckDays days is below the 30-day floor - refusing to run to prevent mass account changes." }

    $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' | Where-Object { $_ })
    if ($Users.Count -eq 0) { return @{ Current = $null } }

    $Cutoff = (Get-Date).AddDays(-$CheckDays).ToUniversalTime()
    $Inactive = @($Users | Where-Object {
            $_.userType -eq 'Member' -and
            $_.accountEnabled -eq $true -and
            $_.onPremisesSyncEnabled -ne $true -and
            $_.createdDateTime -and ([datetime]$_.createdDateTime).ToUniversalTime() -le $Cutoff -and
            $_.signInActivity -and $_.signInActivity.lastSuccessfulSignInDateTime -and
            ([datetime]$_.signInActivity.lastSuccessfulSignInDateTime).ToUniversalTime() -le $Cutoff
        })

    if ($Inactive.Count -gt 0) {
        $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        $Reactivated = @(try {
                $Audits = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Enable account' and activityDateTime ge $AuditLookup&`$select=targetResources" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter
                @($Audits | ForEach-Object { $_.targetResources[0].id }) | Select-Object -Unique
            } catch {
                Write-Information "Baselines: reactivation audit lookup on $TenantFilter failed: $($_.Exception.Message)"
                @()
            })
        $Inactive = @($Inactive | Where-Object { $Reactivated -notcontains $_.id })
    }

    # Operator-excluded accounts (breakglass, service accounts) are never offenders -
    # disabling a breakglass account through an inactivity sweep is how lockouts happen.
    $ExcludedUsers = @(@($Item.Variables.excludedUsers) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
    if ($ExcludedUsers.Count -gt 0) {
        $Inactive = @($Inactive | Where-Object { "$($_.userPrincipalName)" -notin $ExcludedUsers })
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Inactive.userPrincipalName | Sort-Object)
            targets   = @($Inactive | ForEach-Object { [PSCustomObject]@{ id = "$($_.id)" } })
        }
    }
}
