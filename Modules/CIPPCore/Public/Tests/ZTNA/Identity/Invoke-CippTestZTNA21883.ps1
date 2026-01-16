function Invoke-CippTestZTNA21883 {
    <#
    .SYNOPSIS
    Checks if workload identities are configured with risk-based policies

    .DESCRIPTION
    Verifies that Conditional Access policies exist that:
    - Block authentication based on service principal risk
    - Are enabled
    - Target service principals

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #tested
    try {
        # Get Conditional Access policies from cache
        $Policies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $Policies) {
            $TestParams = @{
                TestId               = 'ZTNA21883'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'No Conditional Access policies found in cache.'
                Risk                 = 'Medium'
                Name                 = 'Workload identities configured with risk-based policies'
                UserImpact           = 'High'
                ImplementationEffort = 'Low'
                Category             = 'Access control'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Filter for policies that:
        # - Block authentication
        # - Include service principals
        # - Are enabled
        $MatchedPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($Policy in $Policies) {
            $blocksAuth = $false
            if ($Policy.grantControls.builtInControls) {
                foreach ($control in $Policy.grantControls.builtInControls) {
                    if ($control -eq 'block') {
                        $blocksAuth = $true
                        break
                    }
                }
            }

            $includesSP = $false
            if ($Policy.conditions.clientApplications.includeServicePrincipals) {
                $includesSP = $true
            }

            $isEnabled = $Policy.state -eq 'enabled'

            if ($blocksAuth -and $includesSP -and $isEnabled) {
                $MatchedPolicies.Add($Policy)
            }
        }

        # Determine pass/fail
        if ($MatchedPolicies.Count -ge 1) {
            $Status = 'Passed'
            $ResultMarkdown = "✅ **Pass**: Workload identities are protected by risk-based Conditional Access policies.`n`n"
            $ResultMarkdown += "## Matching policies`n`n"
            $ResultMarkdown += "| Policy name | State | Service principals | Grant controls |`n"
            $ResultMarkdown += "| :---------- | :---- | :----------------- | :------------- |`n"

            foreach ($Policy in $MatchedPolicies) {
                $policyLink = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)"
                $policyName = if ($Policy.displayName) { $Policy.displayName } else { 'Unnamed' }
                $spTargets = if ($Policy.conditions.clientApplications.includeServicePrincipals) {
                    ($Policy.conditions.clientApplications.includeServicePrincipals | Select-Object -First 3) -join ', '
                    if ($Policy.conditions.clientApplications.includeServicePrincipals.Count -gt 3) {
                        $spTargets += " (and $($Policy.conditions.clientApplications.includeServicePrincipals.Count - 3) more)"
                    }
                    $spTargets
                } else {
                    'None'
                }
                $grants = if ($Policy.grantControls.builtInControls) {
                    $Policy.grantControls.builtInControls -join ', '
                } else {
                    'None'
                }
                $ResultMarkdown += "| [$policyName]($policyLink) | $($Policy.state) | $spTargets | $grants |`n"
            }
        } else {
            $Status = 'Failed'
            $ResultMarkdown = "❌ **Fail**: No Conditional Access policies found that protect workload identities with risk-based controls.`n`n"
            $ResultMarkdown += 'Workload identities should be protected by policies that block authentication when service principal risk is detected.'
        }

        $TestParams = @{
            TestId               = 'ZTNA21883'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'Medium'
            Name                 = 'Workload identities configured with risk-based policies'
            UserImpact           = 'High'
            ImplementationEffort = 'Low'
            Category             = 'Access control'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA21883'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'Medium'
            Name                 = 'Workload identities configured with risk-based policies'
            UserImpact           = 'High'
            ImplementationEffort = 'Low'
            Category             = 'Access control'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21883 failed: $($_.Exception.Message)" -sev Error
    }
}
