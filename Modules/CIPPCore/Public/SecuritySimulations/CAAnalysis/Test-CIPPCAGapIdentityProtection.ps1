function Test-CIPPCAGapIdentityProtection {
    <#
    .SYNOPSIS
        Tenant-wide check for risk-based Conditional Access (user risk and sign-in risk conditions).
    .DESCRIPTION
        Raises one High finding when no enabled policy uses user risk levels as a condition and another High
        finding when no enabled policy uses sign-in risk levels.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    if ($Context.Licenses.HasEntraIdP2 -ne $true) { return @() }

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Templates = $Context.Data.Reference.templates

    $HasUserRiskPolicy = @($Context.Enabled | Where-Object { @($_.conditions.userRiskLevels).Count -gt 0 }).Count -gt 0
    $HasSignInRiskPolicy = @($Context.Enabled | Where-Object { @($_.conditions.signInRiskLevels).Count -gt 0 }).Count -gt 0

    if (-not $HasUserRiskPolicy) {
        $Params = @{
            Severity         = 'High'
            Category         = 'Risk-based access'
            Title            = 'No policy responds when Microsoft flags an account as likely compromised'
            Description      = 'Microsoft continuously rates each account for signs of compromise, such as credentials found in leaks or unusual behavior. Without a policy acting on that rating, a compromised account keeps working until someone notices by hand.'
            Remediation      = 'Require high-risk users to re-verify and reset their credentials, or block them, with the emergency-access accounts excluded.'
            CaTemplate       = "$($Templates.userRisk)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies#user-risk-policy'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    if (-not $HasSignInRiskPolicy) {
        $Params = @{
            Severity         = 'High'
            Category         = 'Risk-based access'
            Title            = 'No policy responds when Microsoft rates a sign-in as suspicious'
            Description      = 'Microsoft scores every sign-in in real time on signals such as anonymous networks, impossible travel and password-spray patterns. Without a policy acting on that score, someone with a valid password can sign in from anywhere without any extra check.'
            Remediation      = 'Require multifactor authentication for medium- and high-risk sign-ins and consider blocking high-risk sign-ins outright, with the emergency-access accounts excluded.'
            CaTemplate       = "$($Templates.signInRisk)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/id-protection/howto-identity-protection-configure-risk-policies#sign-in-risk-policy'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
