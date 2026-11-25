function Get-CIPPPrivilegedUserTaskTarget {
    <#
    .SYNOPSIS
        Returns the users a scheduled command changes in a way Microsoft treats as sensitive on privileged users.
    .DESCRIPTION
        Nothing is returned for any other command. Unresolved %variable% values are skipped: a trigger task only
        knows its users once the delta query has run. JIT admin is left out so its expiry tasks always remove the
        access they granted.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [System.Collections.IDictionary]$Parameters,
        [string]$TenantFilter
    )

    $SensitiveCommands = @(
        'Set-CIPPResetPassword', 'Set-CIPPRequirePasswordChange', 'Remove-CIPPUser', 'Set-CIPPSignInState', 'Revoke-CIPPSessions',
        'Remove-CIPPUserMFA', 'New-CIPPTAP', 'Set-CIPPPerUserMFA', 'Clear-CIPPOnPremisesAttributes', 'Clear-CIPPImmutableId',
        'Set-CIPPUser', 'Invoke-CIPPOffboardingJob', 'Invoke-CIPPOnboardingJob', 'Invoke-CIPPBecContainment', 'Start-CIPPBecContainmentJob', 'Invoke-CIPPBecRelease'
    )
    if ($Command -notin $SensitiveCommands -or -not $Parameters) { return }

    if ($Command -eq 'Invoke-CIPPBecRelease') {
        return (Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $Parameters['CaseId']).UserPrincipalName
    }

    if ($Command -eq 'Invoke-CIPPOnboardingJob') {
        # Only the account steps are sensitive on a privileged user; mailbox, OneDrive and group steps are not.
        $Options = $Parameters['Options']
        if ($Options -is [string]) { $Options = $Options | ConvertFrom-Json }
        $AccountSteps = @(@($Options.Fixes).Key).Where({ $_ -in 'EnableSignIn', 'ResetPassword', 'IssueTAP' })
        if ($AccountSteps.Count -eq 0) { return }
    }

    foreach ($Key in @($Parameters.Keys)) {
        $Value = if ($Key -eq 'UserObj') { $Parameters[$Key].id } elseif ($Key -in 'UserID', 'UserPrincipalName', 'Username') { $Parameters[$Key] }
        foreach ($Item in @($Value)) {
            $Target = [string]($Item.value ?? $Item)
            if ($Target -and $Target -notmatch '^%.*%$') { $Target }
        }
    }
}
