function Get-CIPPLastSignInDateTime {
    <#
    .SYNOPSIS
        Returns the most recent sign-in timestamp from a Graph signInActivity object, in UTC.
    .DESCRIPTION
        Takes the newest of lastSignInDateTime (interactive), lastNonInteractiveSignInDateTime and
        lastSuccessfulSignInDateTime. The first two record the last sign-in attempt whether it
        succeeded or not, which is the view the Entra portal and the inactive-user alerts give;
        the third can run ahead of both, so leaving it out would report a recently active user
        as stale. Returns $null when the user has no sign-in activity on record.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($SignInActivity)

    if (-not $SignInActivity) { return $null }

    $Latest = $null
    foreach ($Property in 'lastSignInDateTime', 'lastNonInteractiveSignInDateTime', 'lastSuccessfulSignInDateTime') {
        $Value = $SignInActivity.$Property
        if ([string]::IsNullOrWhiteSpace("$Value")) { continue }
        try {
            $Candidate = ([datetime]$Value).ToUniversalTime()
        } catch {
            continue
        }
        if ($null -eq $Latest -or $Candidate -gt $Latest) { $Latest = $Candidate }
    }
    return $Latest
}
