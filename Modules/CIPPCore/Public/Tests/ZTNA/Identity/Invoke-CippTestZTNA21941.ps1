function Invoke-CippTestZTNA21941 {
    <#
    .SYNOPSIS
    Checks if token protection policies are enforced for Windows platform

    .DESCRIPTION
    Verifies that Conditional Access policies with token protection (secureSignInSession) are
    configured for Windows devices, requiring Office 365 and Microsoft Graph access through
    protected sessions to prevent token theft.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #Tested
    try {
        # Get CA policies from cache
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            $TestParams = @{
                TestId               = 'ZTNA21941'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve Conditional Access policies from cache.'
                Risk                 = 'High'
                Name                 = 'Implement token protection policies'
                UserImpact           = 'Medium'
                ImplementationEffort = 'Medium'
                Category             = 'Access control'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Required Office 365 and Graph app IDs
        $RequiredAppIds = @(
            '00000002-0000-0ff1-ce00-000000000000',  # Office 365 Exchange Online
            '00000003-0000-0ff1-ce00-000000000000'   # Microsoft Graph
        )

        # Filter for policies with Windows platform and secureSignInSession control
        $TokenProtectionPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($policy in $CAPolicies) {
            # Check if policy has Windows platform
            $hasWindows = $false
            if ($policy.conditions.platforms.includePlatforms) {
                if ($policy.conditions.platforms.includePlatforms -contains 'windows' -or
                    $policy.conditions.platforms.includePlatforms -contains 'all') {
                    $hasWindows = $true
                }
            }

            # Check if policy has secureSignInSession control
            $hasTokenProtection = $false
            if ($policy.sessionControls -and $policy.sessionControls.signInFrequency) {
                if ($policy.sessionControls.signInFrequency.isEnabled -eq $true -and
                    $policy.sessionControls.signInFrequency.authenticationType -eq 'primaryAndSecondaryAuthentication') {
                    $hasTokenProtection = $true
                }
            }

            # Alternative check for newer API format
            if (-not $hasTokenProtection -and $policy.sessionControls) {
                foreach ($prop in $policy.sessionControls.PSObject.Properties) {
                    if ($prop.Name -like '*secureSignIn*' -or $prop.Name -like '*tokenProtection*') {
                        if ($prop.Value.isEnabled -eq $true) {
                            $hasTokenProtection = $true
                            break
                        }
                    }
                }
            }

            if ($hasWindows -and $hasTokenProtection -and $policy.state -eq 'enabled') {
                # Check if policy includes users
                $hasUsers = $false
                if ($policy.conditions.users.includeUsers -and $policy.conditions.users.includeUsers.Count -gt 0) {
                    $hasUsers = $true
                }

                # Check if policy includes required apps
                $hasRequiredApps = $false
                if ($policy.conditions.applications.includeApplications) {
                    $includeAll = $policy.conditions.applications.includeApplications -contains 'All'
                    if ($includeAll) {
                        $hasRequiredApps = $true
                    } else {
                        $foundApps = 0
                        foreach ($appId in $RequiredAppIds) {
                            if ($policy.conditions.applications.includeApplications -contains $appId) {
                                $foundApps++
                            }
                        }
                        if ($foundApps -eq $RequiredAppIds.Count) {
                            $hasRequiredApps = $true
                        }
                    }
                }

                $policyStatus = 'Unknown'
                if ($hasUsers -and $hasRequiredApps) {
                    $policyStatus = 'Pass'
                } elseif (-not $hasUsers) {
                    $policyStatus = 'No users targeted'
                } elseif (-not $hasRequiredApps) {
                    $policyStatus = 'Missing required apps'
                }

                $TokenProtectionPolicies.Add([PSCustomObject]@{
                        Name            = $policy.displayName
                        State           = $policy.state
                        HasUsers        = $hasUsers
                        HasRequiredApps = $hasRequiredApps
                        Status          = $policyStatus
                    })
            }
        }

        # Determine overall status
        $PassingPolicies = $TokenProtectionPolicies | Where-Object { $_.Status -eq 'Pass' }
        $Status = if ($PassingPolicies.Count -gt 0) { 'Passed' } else { 'Failed' }

        # Build result markdown
        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Token protection policies are properly configured for Windows devices.`n`n"
            $ResultMarkdown += "Token protection binds authentication tokens to devices, making stolen tokens unusable on other devices.`n`n"
        } else {
            if ($TokenProtectionPolicies.Count -eq 0) {
                $ResultMarkdown = "❌ **Fail**: No token protection policies found for Windows devices.`n`n"
                $ResultMarkdown += "Without token protection, authentication tokens can be stolen and replayed from other devices.`n`n"
                $ResultMarkdown += '[Create token protection policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)'
            } else {
                $ResultMarkdown = "❌ **Fail**: Token protection policies exist but are not properly configured.`n`n"
                $ResultMarkdown += "Policies must target users and include both Office 365 and Microsoft Graph applications.`n`n"
            }
        }

        if ($TokenProtectionPolicies.Count -gt 0) {
            $ResultMarkdown += "## Token protection policies`n`n"
            $ResultMarkdown += "| Policy Name | State | Has Users | Has Required Apps | Status |`n"
            $ResultMarkdown += "| :---------- | :---- | :-------- | :---------------- | :----- |`n"

            foreach ($policy in $TokenProtectionPolicies) {
                $stateIcon = if ($policy.State -eq 'enabled') { '✅' } else { '❌' }
                $usersIcon = if ($policy.HasUsers) { '✅' } else { '❌' }
                $appsIcon = if ($policy.HasRequiredApps) { '✅' } else { '❌' }
                $statusIcon = if ($policy.Status -eq 'Pass') { '✅' } else { '❌' }

                $ResultMarkdown += "| $($policy.Name) | $stateIcon $($policy.State) | $usersIcon | $appsIcon | $statusIcon $($policy.Status) |`n"
            }

            $ResultMarkdown += "`n[Review policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)"
        }

        $TestParams = @{
            TestId               = 'ZTNA21941'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'High'
            Name                 = 'Implement token protection policies'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Access control'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA21941'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'High'
            Name                 = 'Implement token protection policies'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Access control'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21941 failed: $($_.Exception.Message)" -sev Error
    }
}
