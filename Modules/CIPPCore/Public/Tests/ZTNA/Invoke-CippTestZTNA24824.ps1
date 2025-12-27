function Invoke-CippTestZTNA24824 {
    <#
    .SYNOPSIS
    Checks if Conditional Access policies block access from noncompliant devices

    .DESCRIPTION
    Verifies that enabled Conditional Access policies exist that require device compliance,
    covering all platforms (Windows, macOS, iOS, Android) or a policy with no platform filter.

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
                TestId               = 'ZTNA24824'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve Conditional Access policies from cache.'
                Risk                 = 'High'
                Name                 = 'CA policies block access from noncompliant devices'
                UserImpact           = 'Medium'
                ImplementationEffort = 'Medium'
                Category             = 'Device security'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Filter for enabled policies with compliantDevice control
        $CompliantDevicePolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($policy in $CAPolicies) {
            if ($policy.state -eq 'enabled' -and
                $policy.grantControls -and
                $policy.grantControls.builtInControls -and
                ($policy.grantControls.builtInControls -contains 'compliantDevice')) {
                $CompliantDevicePolicies.Add($policy)
            }
        }

        if ($CompliantDevicePolicies.Count -eq 0) {
            $TestParams = @{
                TestId               = 'ZTNA24824'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Failed'
                ResultMarkdown       = "❌ **Fail**: No Conditional Access policies found that block access from noncompliant devices.`n`n[Create policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)"
                Risk                 = 'High'
                Name                 = 'CA policies block access from noncompliant devices'
                UserImpact           = 'Medium'
                ImplementationEffort = 'Medium'
                Category             = 'Device security'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Track platform coverage
        $PlatformCoverage = @{
            'windows' = $false
            'macOS'   = $false
            'iOS'     = $false
            'android' = $false
        }
        $AllPlatformsPolicy = $false

        $PolicyDetails = [System.Collections.Generic.List[object]]::new()

        foreach ($policy in $CompliantDevicePolicies) {
            $platforms = 'All platforms'

            if ($policy.conditions.platforms.includePlatforms) {
                if ($policy.conditions.platforms.includePlatforms -contains 'all') {
                    $AllPlatformsPolicy = $true
                    $platforms = 'All platforms'
                } else {
                    $platformList = $policy.conditions.platforms.includePlatforms -join ', '
                    $platforms = $platformList

                    # Track individual platform coverage
                    foreach ($platform in $policy.conditions.platforms.includePlatforms) {
                        $lowerPlatform = $platform.ToLower()
                        if ($PlatformCoverage.ContainsKey($lowerPlatform)) {
                            $PlatformCoverage[$lowerPlatform] = $true
                        }
                    }
                }
            } else {
                # No platform filter = applies to all platforms
                $AllPlatformsPolicy = $true
            }

            $PolicyDetails.Add([PSCustomObject]@{
                    Name      = $policy.displayName
                    Platforms = $platforms
                })
        }

        # Check if all platforms are covered (either by a single policy or combination)
        $AllCovered = $AllPlatformsPolicy -or (
            $PlatformCoverage['windows'] -and
            $PlatformCoverage['macOS'] -and
            $PlatformCoverage['iOS'] -and
            $PlatformCoverage['android']
        )

        $Status = if ($AllCovered) { 'Passed' } else { 'Failed' }

        # Build result markdown
        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Conditional Access policies block noncompliant devices across all platforms.`n`n"
        } else {
            $ResultMarkdown = "❌ **Fail**: Conditional Access policies do not cover all device platforms.`n`n"
            $missingPlatforms = [System.Collections.Generic.List[string]]::new()
            foreach ($key in $PlatformCoverage.Keys) {
                if (-not $PlatformCoverage[$key]) {
                    $missingPlatforms.Add($key)
                }
            }
            if ($missingPlatforms.Count -gt 0) {
                $ResultMarkdown += "**Missing platform coverage**: $($missingPlatforms -join ', ')`n`n"
            }
        }

        $ResultMarkdown += "## Compliant device policies`n`n"
        $ResultMarkdown += "| Policy Name | Platforms |`n"
        $ResultMarkdown += "| :---------- | :-------- |`n"

        foreach ($detail in $PolicyDetails) {
            $ResultMarkdown += "| $($detail.Name) | $($detail.Platforms) |`n"
        }

        $ResultMarkdown += "`n[Review policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)"

        $TestParams = @{
            TestId               = 'ZTNA24824'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'High'
            Name                 = 'CA policies block access from noncompliant devices'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Device security'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA24824'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'High'
            Name                 = 'CA policies block access from noncompliant devices'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Device security'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA24824 failed: $($_.Exception.Message)" -sev Error
    }
}
