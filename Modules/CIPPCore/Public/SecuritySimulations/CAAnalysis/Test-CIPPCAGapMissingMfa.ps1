function Test-CIPPCAGapMissingMfa {
    <#
    .SYNOPSIS
        Flags grant policies that do not require MFA or an authentication strength.
    .DESCRIPTION
        Skips disabled policies, policies with no grant controls, block policies, workload/agent-identity
        policies (includeUsers = None with no groups or roles) and policies whose controls are all strong
        DeviceTrust or AppProtection controls (a legitimate standalone layer).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Groups = $Context.Data.Reference.equivalentStrengthGroups

    foreach ($Policy in @($Context.Policies)) {
        if ($Policy.state -eq 'disabled') { continue }
        $Grant = $Policy.grantControls
        $Controls = @($Grant.builtInControls)
        if (-not $Grant.present -or $Controls.Count -eq 0) { continue }
        if ($Controls -contains 'block') { continue }

        $RequiresMfa = ($Controls -contains 'mfa') -or ($null -ne $Grant.authenticationStrength)
        if ($RequiresMfa) { continue }

        $Users = $Policy.conditions.users
        $RealIncludeUsers = @($Users.includeUsers | Where-Object { $_ -ne 'None' })
        $TargetsUsers = ($RealIncludeUsers.Count -gt 0) -or (@($Users.includeGroups).Count -gt 0) -or (@($Users.includeRoles).Count -gt 0)
        if (-not $TargetsUsers) { continue }

        $AllStrongNonMfa = @($Controls | Where-Object {
                $ControlName = $_
                $null -eq $Groups.$ControlName
            }).Count -eq 0
        if ($AllStrongNonMfa) { continue }

        $Params = @{
            Severity         = 'Medium'
            Category         = 'Grant requirements'
            Title            = 'Policy grants access without requiring multifactor authentication'
            Description      = "Access is granted on the basis of $($Controls -join ', ') alone. A stolen password is enough to pass this policy, because a second factor is not part of what it asks for."
            Remediation      = 'Make multifactor authentication part of what this policy requires, ideally through an authentication strength.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-mfa-strength'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
