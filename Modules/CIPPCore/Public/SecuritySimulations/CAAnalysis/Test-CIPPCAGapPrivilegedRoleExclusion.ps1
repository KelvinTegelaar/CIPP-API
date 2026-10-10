function Test-CIPPCAGapPrivilegedRoleExclusion {
    <#
    .SYNOPSIS
        Flags policies that exclude highly privileged directory roles.
    .DESCRIPTION
        Per policy (any state): every excluded role that is in the high-privilege list produces one finding
        per policy.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $RoleNames = $Context.Data.HighPrivilegeRoleNames
    $CriticalRoleIds = $Context.Data.CriticalRoleIds
    $RegisterSecurityInfo = "$($Context.Data.Reference.registerSecurityInfoAction)"

    foreach ($Policy in @($Context.Policies)) {
        $ExcludedRoles = @($Policy.conditions.users.excludeRoles)
        if ($ExcludedRoles.Count -eq 0) { continue }

        $ExcludedHighPriv = [System.Collections.Generic.List[object]]::new()
        foreach ($RoleId in $ExcludedRoles) {
            $Name = $RoleNames["$RoleId".ToLowerInvariant()]
            if ($Name) {
                $ExcludedHighPriv.Add([PSCustomObject]@{ id = "$RoleId"; name = "$Name"; critical = $CriticalRoleIds.Contains("$RoleId") })
            }
        }
        if ($ExcludedHighPriv.Count -eq 0) { continue }

        $HasCritical = @($ExcludedHighPriv | Where-Object { $_.critical }).Count -gt 0
        $CriticalNames = @($ExcludedHighPriv | Where-Object { $_.critical } | ForEach-Object { $_.name })
        $AllNames = @($ExcludedHighPriv | ForEach-Object { $_.name })
        $ExcludedLower = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Entry in $ExcludedHighPriv) { $null = $ExcludedLower.Add($Entry.id) }

        $CoveringPolicy = $null
        foreach ($Other in @($Context.Policies)) {
            if ($Other.id -eq $Policy.id -or $Other.state -eq 'disabled') { continue }
            $OtherUsers = $Other.conditions.users
            $EnforcesMfa = (@($Other.grantControls.builtInControls) -contains 'mfa') -or ($null -ne $Other.grantControls.authenticationStrength)
            if (-not $EnforcesMfa) { continue }
            $IncludeRoles = @($OtherUsers.includeRoles | ForEach-Object { "$_".ToLowerInvariant() })
            $IncludesViaRoles = @($ExcludedLower | Where-Object { $IncludeRoles -notcontains $_.ToLowerInvariant() }).Count -eq 0
            $OtherExcludeRoles = @($OtherUsers.excludeRoles | ForEach-Object { "$_".ToLowerInvariant() })
            $ReExcludes = @($ExcludedLower | Where-Object { $OtherExcludeRoles -contains $_.ToLowerInvariant() }).Count -gt 0
            $IncludesViaAllUsers = (@($OtherUsers.includeUsers) -contains 'All') -and -not $ReExcludes
            if ($IncludesViaRoles -or $IncludesViaAllUsers) { $CoveringPolicy = $Other; break }
        }

        $Controls = @($Policy.grantControls.builtInControls)
        $RequiresMfa = ($Controls -contains 'mfa') -or ($null -ne $Policy.grantControls.authenticationStrength)
        $Blocks = $Controls -contains 'block'
        $TargetsSecurityRegistration = @($Policy.conditions.applications.includeUserActions) -contains $RegisterSecurityInfo
        $TargetsAllApps = @($Policy.conditions.applications.includeApplications) -contains 'All'

        $Severity = if ($HasCritical) { 'Critical' } else { 'High' }
        if ($TargetsSecurityRegistration) {
            $ScenarioNames = if ($CriticalNames.Count -gt 0) { $CriticalNames -join ', ' } else { $AllNames -join ', ' }
            $AttackScenario = "This policy protects the registration of sign-in methods, yet $ScenarioNames are exempt from it. Someone who takes over one of these administrator accounts can add their own sign-in methods unchallenged and keep access even after a password reset."
            $Severity = 'Critical'
        } elseif ($Blocks) {
            $AttackScenario = "This policy blocks access, yet $($AllNames -join ', ') are exempt from it. The most powerful accounts in the tenant pass where everyone else is stopped."
        } elseif ($RequiresMfa -and $TargetsAllApps) {
            $AttackScenario = "This policy requires multifactor authentication for every application, yet $($AllNames -join ', ') are exempt from it. The accounts an attacker values most can sign in with a password alone."
        } else {
            $AttackScenario = "This policy exempts $($ExcludedHighPriv.Count) privileged role(s): $($AllNames -join ', '). Administrator accounts should face the same or stricter requirements as everyone else, not fewer."
        }
        if ($CoveringPolicy) { $Severity = 'Info' }

        $CoveredNote = if ($CoveringPolicy) {
            $StateLabel = if ($CoveringPolicy.state -eq 'enabledForReportingButNotEnforced') { 'report-only' } else { 'enabled' }
            " A separate policy, $($CoveringPolicy.displayName) ($StateLabel), does appear to cover these roles."
        } else {
            ' No other policy requires multifactor authentication from these roles, so the exemption leaves them without that protection.'
        }

        $TitleSuffix = ''
        if ($HasCritical) { $TitleSuffix += ', including top admin roles' }
        if ($CoveringPolicy) { $TitleSuffix += ' (covered elsewhere)' }

        $Remediation = if ($CoveringPolicy) {
            "Confirm that $($CoveringPolicy.displayName) holds these roles to the same or stricter requirements, and exclude only named emergency-access accounts rather than whole roles."
        } else {
            "Remove the exemption for $($AllNames -join ', ') and exclude only the named emergency-access accounts instead."
        }

        $Affected = [System.Collections.Generic.List[string]]::new()
        $Affected.Add($Policy.displayName)
        if ($CoveringPolicy) { $Affected.Add($CoveringPolicy.displayName) }

        $Params = @{
            Severity         = $Severity
            Category         = 'Administrator coverage'
            Title            = "$($ExcludedHighPriv.Count) privileged role(s) exempt from this policy$TitleSuffix"
            Description      = $AttackScenario + $CoveredNote
            Remediation      = $Remediation
            AffectedPolicies = @($Affected)
            RelatedIds       = @($ExcludedHighPriv | ForEach-Object { $_.id })
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-old-require-mfa-admin'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    $PoliciesExcludingCritical = @($Context.Enabled | Where-Object {
            @($_.conditions.users.excludeRoles | Where-Object { $CriticalRoleIds.Contains("$_") }).Count -gt 0
        })
    if ($PoliciesExcludingCritical.Count -gt 0) {
        $AffectedNames = @($PoliciesExcludingCritical | ForEach-Object { $_.displayName })
        $Params = @{
            Severity         = 'Critical'
            Category         = 'Administrator coverage'
            Title            = "$($PoliciesExcludingCritical.Count) enforced policy(ies) exempt the top administrator roles"
            Description      = "The following policies exempt roles such as Global Administrator or Privileged Role Administrator: $($AffectedNames -join ', '). These are the accounts attackers seek first, and here they receive less protection than a regular user."
            Remediation      = 'Remove the role exemptions from every policy, exclude only two named emergency-access accounts, and require phishing-resistant multifactor authentication from all administrators.'
            AffectedPolicies = $AffectedNames
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-old-require-mfa-admin'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
