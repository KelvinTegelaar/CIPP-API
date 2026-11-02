function Test-CIPPCAGapMfaCoverage {
    <#
    .SYNOPSIS
        Tenant-wide check that some enabled policy requires MFA for All users.
    .DESCRIPTION
        A policy covers MFA for all users when it includes "All" users and requires MFA or an authentication
        strength.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    $IsMfaForAll = {
        param($P)
        (@($P.conditions.users.includeUsers) -contains 'All') -and ((@($P.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $P.grantControls.authenticationStrength))
    }

    $HasMfaForAll = @($Context.Enabled | Where-Object { & $IsMfaForAll $_ }).Count -gt 0
    if ($HasMfaForAll) { return @($Findings) }

    $ReportOnlyMfaForAll = @($Context.ReportOnly | Where-Object { & $IsMfaForAll $_ } | Select-Object -First 1)
    if ($ReportOnlyMfaForAll.Count -gt 0) {
        $Policy = $ReportOnlyMfaForAll[0]
        $Params = @{
            Severity         = 'Medium'
            Category         = 'Multifactor coverage'
            Title            = 'The multifactor policy for all users is in report-only mode'
            Description      = "$($Policy.displayName) would require multifactor authentication from everyone, but it only records what would happen. Until it is enforced, users can still sign in with a password alone."
            Remediation      = 'Enforce the policy once the report-only results show no unexpected impact and the emergency-access accounts are excluded.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-mfa-strength'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    } else {
        $Params = @{
            Severity         = 'Critical'
            Category         = 'Multifactor coverage'
            Title            = 'No policy requires multifactor authentication from all users'
            Description      = 'Nothing in the tenant ensures that every user proves their identity with a second factor. Any account whose password is stolen or guessed can be signed in to directly.'
            Remediation      = 'Require multifactor authentication from all users for all applications as the baseline policy, with only the emergency-access accounts excluded.'
            CaTemplate       = "$($Context.Data.Reference.templates.mfaAllUsers)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-mfa-strength'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
