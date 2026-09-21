function Test-CIPPCAGapProtectedActions {
    <#
    .SYNOPSIS
        Reviews policies that protect Protected Actions (microsoft.directory.* user actions).
    .DESCRIPTION
        For every policy (any state) whose user actions start with "microsoft.directory": basic "Require
        MFA" instead of an authentication strength is High; targeting All users instead of admin roles is
        Medium; a non-phishing- resistant authentication strength is Info; report-only state is Info; an
        enabled policy with no user exclusions (no break-glass path) is Medium.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    foreach ($Policy in @($Context.Policies)) {
        $UserActions = @($Policy.conditions.applications.includeUserActions)
        if ($UserActions.Count -eq 0) { continue }
        $ProtectedActions = @($UserActions | Where-Object { "$_".StartsWith('microsoft.directory') })
        if ($ProtectedActions.Count -eq 0) { continue }

        $Grant = $Policy.grantControls
        $Users = $Policy.conditions.users
        $Controls = @($Grant.builtInControls)
        $ActionList = $ProtectedActions -join ', '
        $UsesBasicMfa = ($Controls -contains 'mfa') -and ($null -eq $Grant.authenticationStrength)
        $UsesAuthStrength = $null -ne $Grant.authenticationStrength

        if ($UsesBasicMfa) {
            $Params = @{
                Severity         = 'High'
                Category         = 'Protected actions'
                Title            = 'Protected administrative actions rely on basic multifactor authentication'
                Description      = "This policy guards sensitive administrative operations but asks only for basic multifactor authentication rather than an authentication strength. Protected actions are designed to work with an authentication strength, so the extra check may not be applied reliably when an administrator performs them. Operations covered: $ActionList."
                Remediation      = 'Require an authentication strength, preferably phishing-resistant, for these protected actions and confirm the administrators involved have registered a suitable method.'
                AffectedPolicies = @($Policy.displayName)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/protected-actions-overview'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }

        $TargetsAllUsers = @($Users.includeUsers) -contains 'All'
        $TargetsAdminRoles = @($Users.includeRoles).Count -gt 0
        if ($TargetsAllUsers -and -not $TargetsAdminRoles) {
            $Params = @{
                Severity         = 'Medium'
                Category         = 'Protected actions'
                Title            = 'Protected administrative actions policy applies to everyone rather than administrators'
                Description      = "Only administrators can perform the operations this policy guards, yet it applies to every user and prompts people who could never carry them out. Operations covered: $ActionList."
                Remediation      = 'Scope the policy to the administrator roles that actually perform these operations, keeping the emergency-access accounts excluded.'
                AffectedPolicies = @($Policy.displayName)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/protected-actions-overview'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }

        if ($UsesAuthStrength) {
            $StrengthName = "$($Grant.authenticationStrength.displayName)"
            if (-not (Test-CIPPCAPolicyPhishingResistant -Policy $Policy -Context $Context)) {
                $Params = @{
                    Severity         = 'Info'
                    Category         = 'Protected actions'
                    Title            = "Protected actions accept ""$StrengthName"" instead of phishing-resistant methods"
                    Description      = "Common multifactor methods such as text messages, codes and push approvals can be captured by a convincing phishing page, and the operations this policy guards are exactly what an attacker with a captured administrator session would go after. Operations covered: $ActionList."
                    Remediation      = 'Move the administrators who perform these operations to phishing-resistant sign-in methods and raise this policy to the phishing-resistant strength. The current setting meets the minimum.'
                    AffectedPolicies = @($Policy.displayName)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/protected-actions-overview'
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
            }
        }

        if ($Policy.state -eq 'enabledForReportingButNotEnforced') {
            $Params = @{
                Severity         = 'Info'
                Category         = 'Protected actions'
                Title            = 'Protected administrative actions policy is not yet enforced'
                Description      = 'The policy is in report-only mode, so administrators can still carry out these sensitive operations without the extra verification. Report-only is a sensible starting point, but it offers no protection until the policy is enforced.'
                Remediation      = 'Enforce the policy once the recorded results show that the administrators involved can meet the requirement.'
                AffectedPolicies = @($Policy.displayName)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/protected-actions-overview'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }

        $HasExclusions = @($Users.excludeUsers).Count -gt 0
        if (-not $HasExclusions -and $Policy.state -eq 'enabled') {
            $Params = @{
                Severity         = 'Medium'
                Category         = 'Protected actions'
                Title            = 'Protected administrative actions policy has no emergency-access exclusion'
                Description      = 'Nobody is exempt from this policy. If the required sign-in method stops working, for example during a service outage, no administrator can perform the operations needed to recover, such as disabling a faulty policy or restoring a role assignment.'
                Remediation      = 'Exclude the emergency-access accounts from this policy and monitor any sign-in by them.'
                AffectedPolicies = @($Policy.displayName)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/protected-actions-overview'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }
    }

    @($Findings)
}
