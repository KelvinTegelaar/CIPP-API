function Test-CIPPCAGapBreakGlass {
    <#
    .SYNOPSIS
        Checks that the detected break-glass account or group is excluded from every user-targeting policy.
    .DESCRIPTION
        Uses the break-glass candidate on the context (the user or group excluded most often across enabled
        and report-only All-users policies).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $BreakGlass = $Context.BreakGlass

    $TargetsUsers = {
        param($P)
        $U = $P.conditions.users
        (@($U.includeUsers | Where-Object { $_ -ne 'None' }).Count -gt 0) -or (@($U.includeGroups).Count -gt 0) -or (@($U.includeRoles).Count -gt 0)
    }
    $IsExcluded = {
        param($P)
        if ($BreakGlass.type -eq 'user') { @($P.conditions.users.excludeUsers) -contains $BreakGlass.id }
        else { @($P.conditions.users.excludeGroups) -contains $BreakGlass.id }
    }

    $AllPolicies = @($Context.Policies)
    $UserTargetingPolicies = @($AllPolicies | Where-Object { & $TargetsUsers $_ })

    if ($BreakGlass) {
        $Label = if ($BreakGlass.type -eq 'user') { 'emergency-access account' } else { 'emergency-access group' }
        $DisplayName = "$($BreakGlass.displayName)"
        $ExcludeTarget = if ($BreakGlass.type -eq 'user') { 'excluded users' } else { 'excluded groups' }

        foreach ($Policy in $UserTargetingPolicies) {
            $Excluded = & $IsExcluded $Policy

            if ($Excluded) {
                $Params = @{
                    Severity         = 'Info'
                    Category         = 'Emergency access'
                    Title            = "The emergency-access $($BreakGlass.type) is excluded from this policy"
                    Description      = "The $Label $DisplayName keeps working even if this policy locks everyone else out."
                    Remediation      = "No change needed. Keep monitoring any sign-in by the $Label and confirm periodically that it still works."
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($BreakGlass.id)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
                continue
            }

            $Controls = @($Policy.grantControls.builtInControls)
            $Blocks = $Controls -contains 'block'
            $RequiresMfa = ($Controls -contains 'mfa') -or ($null -ne $Policy.grantControls.authenticationStrength)
            $RequiresCompliance = ($Controls -contains 'compliantDevice') -or ($Controls -contains 'domainJoinedDevice')
            $TargetsAllUsers = @($Policy.conditions.users.includeUsers) -contains 'All'
            $TargetsAllApps = @($Policy.conditions.applications.includeApplications) -contains 'All'

            $Severity = 'Low'
            if ($Blocks -and $TargetsAllUsers -and $TargetsAllApps) { $Severity = 'High' }
            elseif (($RequiresMfa -or $RequiresCompliance) -and $TargetsAllUsers) { $Severity = 'Medium' }
            elseif ($Blocks -and $TargetsAllUsers) { $Severity = 'Medium' }

            $IsMicrosoftManaged = "$($Policy.displayName)".ToLowerInvariant().Contains('microsoft managed') -or ($null -ne $Policy.templateId)
            if ($IsMicrosoftManaged -and $Policy.state -eq 'disabled') {
                $Params = @{
                    Severity         = 'Info'
                    Category         = 'Emergency access'
                    Title            = "Disabled Microsoft-managed policy does not exclude the emergency-access $($BreakGlass.type)"
                    Description      = "The $Label $DisplayName is not on the exclusion list of this Microsoft-managed policy. Because the policy is switched off, there is no exposure today."
                    Remediation      = "Exclude the $Label $DisplayName before this policy is ever enabled, so emergency access is preserved."
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($BreakGlass.id)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
                }
            } elseif ($Policy.state -eq 'enabledForReportingButNotEnforced') {
                $Params = @{
                    Severity         = 'Medium'
                    Category         = 'Emergency access'
                    Title            = "Report-only policy does not exclude the emergency-access $($BreakGlass.type)"
                    Description      = "The $Label $DisplayName is not on the exclusion list. The policy is in report-only mode, so nothing is enforced yet, but enabling it as it stands could lock out emergency access."
                    Remediation      = "Exclude the $Label $DisplayName before this policy is switched to enforced."
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($BreakGlass.id)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
                }
            } elseif ($Policy.state -eq 'disabled') {
                $Params = @{
                    Severity         = 'Low'
                    Category         = 'Emergency access'
                    Title            = "Disabled policy does not exclude the emergency-access $($BreakGlass.type)"
                    Description      = "The $Label $DisplayName is not on the exclusion list. The policy is switched off, so there is no exposure today, but enabling it as it stands could lock out emergency access."
                    Remediation      = "Exclude the $Label $DisplayName before this policy is enabled."
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($BreakGlass.id)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
                }
            } else {
                $Params = @{
                    Severity         = $Severity
                    Category         = 'Emergency access'
                    Title            = "Enforced policy does not exclude the emergency-access $($BreakGlass.type)"
                    Description      = "The $Label $DisplayName is subject to this enforced policy. If the policy misfires, for example through a faulty multifactor, device or block rule, the $Label is locked out with everyone else and cannot be used to recover."
                    Remediation      = "Add $DisplayName to the $ExcludeTarget of this policy so emergency access survives a lockout."
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($BreakGlass.id)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
                }
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }

        $WithNames = [System.Collections.Generic.List[string]]::new()
        $WithoutNames = [System.Collections.Generic.List[string]]::new()
        $EnabledWithoutCount = 0
        foreach ($Policy in $UserTargetingPolicies) {
            if (& $IsExcluded $Policy) { $WithNames.Add($Policy.displayName) }
            else {
                $WithoutNames.Add($Policy.displayName)
                if ($Policy.state -eq 'enabled') { $EnabledWithoutCount++ }
            }
        }
        $BreakGlassLabel = if ($BreakGlass.type -eq 'user') { 'Emergency-access account' } else { 'Emergency-access group' }
        $TotalPolicyCount = $AllPolicies.Count
        $Overview = "$BreakGlassLabel`: $DisplayName. The tenant has $TotalPolicyCount policies, of which $($UserTargetingPolicies.Count) apply to users; $($WithNames.Count) exclude the $Label and $($WithoutNames.Count) do not."

        if ($WithoutNames.Count -gt 0) {
            $Listed = @($WithoutNames | Select-Object -First 10) -join ', '
            $Overflow = if ($WithoutNames.Count -gt 10) { " and $($WithoutNames.Count - 10) more" } else { '' }
            $Params = @{
                Severity         = if ($EnabledWithoutCount -gt 0) { 'High' } else { 'Medium' }
                Category         = 'Emergency access'
                Title            = "$BreakGlassLabel excluded from only $($WithNames.Count) of $($UserTargetingPolicies.Count) policies that could lock it out"
                Description      = "$Overview $DisplayName was identified as the $($BreakGlassLabel.ToLowerInvariant()) because it is the identity excluded most often across your policies. A single misconfigured policy among the $($WithoutNames.Count) that do not exclude it could lock out every administrator, with no account left to recover access. Policies that do not exclude it: $Listed$Overflow"
                Remediation      = "Exclude $DisplayName from all $($WithoutNames.Count) policies listed and from every future policy, and alert on any sign-in by it."
                AffectedPolicies = @($WithoutNames)
                RelatedIds       = @($BreakGlass.id)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
            }
        } else {
            $Params = @{
                Severity         = 'Info'
                Category         = 'Emergency access'
                Title            = "$BreakGlassLabel is excluded from all $($UserTargetingPolicies.Count) policies that apply to users"
                Description      = "$Overview Emergency access is preserved across the tenant: whatever a policy does, $DisplayName can still sign in to recover from a lockout."
                Remediation      = "Confirm $DisplayName is the intended emergency-access $($BreakGlass.type), keep a second one for redundancy, alert on any sign-in by them and test them regularly."
                AffectedPolicies = @($WithNames)
                RelatedIds       = @($BreakGlass.id)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
            }
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    } else {
        $CriticalPolicies = @($Context.Enabled | Where-Object {
                if (-not (@($_.conditions.users.includeUsers) -contains 'All')) { return $false }
                $C = @($_.grantControls.builtInControls)
                ($C -contains 'mfa') -or ($null -ne $_.grantControls.authenticationStrength) -or ($C -contains 'block') -or ($C -contains 'compliantDevice')
            })
        $CriticalList = @($CriticalPolicies | Select-Object -First 10 | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        $CriticalOverflow = if ($CriticalPolicies.Count -gt 10) { "`nand $($CriticalPolicies.Count - 10) more" } else { '' }
        $TotalPolicyCount = $AllPolicies.Count
        $Params = @{
            Severity         = 'Critical'
            Category         = 'Emergency access'
            Title            = "No emergency-access account could be identified across $TotalPolicyCount policies"
            Description      = "None of the $TotalPolicyCount policies share a consistently excluded user or group, which is how an emergency-access account normally shows up; $($UserTargetingPolicies.Count) of them apply to users. Without such an account, one faulty policy can lock out every administrator, and recovery then depends on Microsoft support and can take days. Policies that most need an exclusion:`n$CriticalList$CriticalOverflow"
            Remediation      = 'Create two dedicated emergency-access accounts, exclude them from every policy and alert on any sign-in by them.'
            AffectedPolicies = @($CriticalPolicies | ForEach-Object { $_.displayName })
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}
