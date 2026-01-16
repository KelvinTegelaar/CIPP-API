function Invoke-CippTestZTNA21892 {
    <#
    .SYNOPSIS
    Verifies that all sign-in activity is restricted to managed devices

    .DESCRIPTION
    Checks for Conditional Access policies that:
    - Apply to all users
    - Apply to all applications
    - Require compliant or hybrid joined devices
    - Are enabled

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
                TestId               = 'ZTNA21892'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'No Conditional Access policies found in cache.'
                Risk                 = 'High'
                Name                 = 'All sign-in activity comes from managed devices'
                UserImpact           = 'High'
                ImplementationEffort = 'High'
                Category             = 'Access control'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Find policies that require managed devices for all users and apps
        $MatchingPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($Policy in $Policies) {
            # Check if applies to all users
            $appliesToAllUsers = $false
            if ($Policy.conditions.users.includeUsers) {
                foreach ($user in $Policy.conditions.users.includeUsers) {
                    if ($user -eq 'All') {
                        $appliesToAllUsers = $true
                        break
                    }
                }
            }

            # Check if applies to all apps
            $appliesToAllApps = $false
            if ($Policy.conditions.applications.includeApplications) {
                foreach ($app in $Policy.conditions.applications.includeApplications) {
                    if ($app -eq 'All') {
                        $appliesToAllApps = $true
                        break
                    }
                }
            }

            # Check if requires compliant or hybrid joined device
            $requiresCompliantDevice = $false
            $requiresHybridJoined = $false
            if ($Policy.grantControls.builtInControls) {
                foreach ($control in $Policy.grantControls.builtInControls) {
                    if ($control -eq 'compliantDevice') {
                        $requiresCompliantDevice = $true
                    }
                    if ($control -eq 'domainJoinedDevice') {
                        $requiresHybridJoined = $true
                    }
                }
            }

            $isEnabled = $Policy.state -eq 'enabled'

            # Policy matches if enabled, applies to all users/apps, and requires managed device
            if ($isEnabled -and $appliesToAllUsers -and $appliesToAllApps -and ($requiresCompliantDevice -or $requiresHybridJoined)) {
                $MatchingPolicies.Add([PSCustomObject]@{
                        PolicyId           = $Policy.id
                        PolicyState        = $Policy.state
                        DisplayName        = $Policy.displayName
                        AllUsers           = $appliesToAllUsers
                        AllApps            = $appliesToAllApps
                        CompliantDevice    = $requiresCompliantDevice
                        HybridJoinedDevice = $requiresHybridJoined
                        IsFullyCompliant   = $isEnabled -and $appliesToAllUsers -and $appliesToAllApps -and ($requiresCompliantDevice -or $requiresHybridJoined)
                    })
            }
        }

        # Determine pass/fail
        if ($MatchingPolicies.Count -gt 0) {
            $Status = 'Passed'
            $ResultMarkdown = "✅ **Pass**: Conditional Access policies require managed devices for all sign-in activity.`n`n"
            $ResultMarkdown += "## Matching policies`n`n"
            $ResultMarkdown += "| Policy name | State | All users | All apps | Compliant device | Hybrid joined |`n"
            $ResultMarkdown += "| :---------- | :---- | :-------- | :------- | :--------------- | :------------ |`n"

            foreach ($Policy in $MatchingPolicies) {
                $policyLink = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.PolicyId)"
                $policyName = if ($Policy.DisplayName) { $Policy.DisplayName } else { 'Unnamed' }
                $allUsers = if ($Policy.AllUsers) { '✅' } else { '❌' }
                $allApps = if ($Policy.AllApps) { '✅' } else { '❌' }
                $compliant = if ($Policy.CompliantDevice) { '✅' } else { '❌' }
                $hybrid = if ($Policy.HybridJoinedDevice) { '✅' } else { '❌' }

                $ResultMarkdown += "| [$policyName]($policyLink) | $($Policy.PolicyState) | $allUsers | $allApps | $compliant | $hybrid |`n"
            }
        } else {
            $Status = 'Failed'
            $ResultMarkdown = "❌ **Fail**: No Conditional Access policies found that require managed devices for all sign-in activity.`n`n"
            $ResultMarkdown += 'Organizations should enforce that all sign-ins come from managed devices (compliant or hybrid Azure AD joined) to ensure security controls are applied.'
        }

        $TestParams = @{
            TestId               = 'ZTNA21892'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'High'
            Name                 = 'All sign-in activity comes from managed devices'
            UserImpact           = 'High'
            ImplementationEffort = 'High'
            Category             = 'Access control'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA21892'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'High'
            Name                 = 'All sign-in activity comes from managed devices'
            UserImpact           = 'High'
            ImplementationEffort = 'High'
            Category             = 'Access control'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21892 failed: $($_.Exception.Message)" -sev Error
    }
}
