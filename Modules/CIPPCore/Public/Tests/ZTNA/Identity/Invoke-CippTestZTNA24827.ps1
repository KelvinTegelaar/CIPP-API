function Invoke-CippTestZTNA24827 {
    <#
    .SYNOPSIS
    Checks if Conditional Access policies block unmanaged mobile apps

    .DESCRIPTION
    Verifies that enabled Conditional Access policies exist that require compliant applications
    for iOS and Android platforms, preventing unmanaged apps from accessing corporate data.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #Tested - Device

    try {
        # Get CA policies from cache
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            $TestParams = @{
                TestId               = 'ZTNA24827'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Skipped'
                ResultMarkdown       = 'Unable to retrieve Conditional Access policies from cache.'
                Risk                 = 'Medium'
                Name                 = 'CA policies block unmanaged mobile apps'
                UserImpact           = 'Medium'
                ImplementationEffort = 'Medium'
                Category             = 'Application security'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Filter for enabled policies with compliantApplication control for mobile platforms
        $CompliantAppPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($policy in $CAPolicies) {
            if ($policy.state -eq 'enabled' -and
                $policy.grantControls -and
                $policy.grantControls.builtInControls -and
                ($policy.grantControls.builtInControls -contains 'compliantApplication')) {

                # Check if policy applies to iOS or Android
                $appliesToMobile = $false
                if ($policy.conditions.platforms.includePlatforms) {
                    if ($policy.conditions.platforms.includePlatforms -contains 'all' -or
                        $policy.conditions.platforms.includePlatforms -contains 'iOS' -or
                        $policy.conditions.platforms.includePlatforms -contains 'android') {
                        $appliesToMobile = $true
                    }
                } else {
                    # No platform filter = applies to all platforms including mobile
                    $appliesToMobile = $true
                }

                if ($appliesToMobile) {
                    $CompliantAppPolicies.Add($policy)
                }
            }
        }

        if ($CompliantAppPolicies.Count -eq 0) {
            $TestParams = @{
                TestId               = 'ZTNA24827'
                TenantFilter         = $Tenant
                TestType             = 'ZeroTrustNetworkAccess'
                Status               = 'Failed'
                ResultMarkdown       = "❌ **Fail**: No Conditional Access policies found that block unmanaged mobile apps.`n`n[Create policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)"
                Risk                 = 'Medium'
                Name                 = 'CA policies block unmanaged mobile apps'
                UserImpact           = 'Medium'
                ImplementationEffort = 'Medium'
                Category             = 'Application security'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Track platform coverage for iOS and Android
        $PlatformCoverage = @{
            'iOS'     = $false
            'android' = $false
        }
        $AllPlatformsPolicy = $false

        $PolicyDetails = [System.Collections.Generic.List[object]]::new()

        foreach ($policy in $CompliantAppPolicies) {
            $platforms = 'All platforms'

            if ($policy.conditions.platforms.includePlatforms) {
                if ($policy.conditions.platforms.includePlatforms -contains 'all') {
                    $AllPlatformsPolicy = $true
                    $platforms = 'All platforms'
                } else {
                    $platformList = $policy.conditions.platforms.includePlatforms -join ', '
                    $platforms = $platformList

                    # Track individual platform coverage
                    if ($policy.conditions.platforms.includePlatforms -contains 'iOS') {
                        $PlatformCoverage['iOS'] = $true
                    }
                    if ($policy.conditions.platforms.includePlatforms -contains 'android') {
                        $PlatformCoverage['android'] = $true
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

        # Check if both iOS and Android are covered
        $BothCovered = $AllPlatformsPolicy -or ($PlatformCoverage['iOS'] -and $PlatformCoverage['android'])

        $Status = if ($BothCovered) { 'Passed' } else { 'Failed' }

        # Build result markdown
        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Conditional Access policies block unmanaged apps on both iOS and Android platforms.`n`n"
        } else {
            $ResultMarkdown = "❌ **Fail**: Conditional Access policies do not cover all mobile platforms.`n`n"
            $missingPlatforms = [System.Collections.Generic.List[string]]::new()
            if (-not $PlatformCoverage['iOS']) {
                $missingPlatforms.Add('iOS')
            }
            if (-not $PlatformCoverage['android']) {
                $missingPlatforms.Add('android')
            }
            if ($missingPlatforms.Count -gt 0) {
                $ResultMarkdown += "**Missing platform coverage**: $($missingPlatforms -join ', ')`n`n"
            }
        }

        $ResultMarkdown += "## Compliant application policies`n`n"
        $ResultMarkdown += "| Policy Name | Platforms |`n"
        $ResultMarkdown += "| :---------- | :-------- |`n"

        foreach ($detail in $PolicyDetails) {
            $ResultMarkdown += "| $($detail.Name) | $($detail.Platforms) |`n"
        }

        $ResultMarkdown += "`n[Review policies](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies)"

        $TestParams = @{
            TestId               = 'ZTNA24827'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = $Status
            ResultMarkdown       = $ResultMarkdown
            Risk                 = 'Medium'
            Name                 = 'CA policies block unmanaged mobile apps'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Application security'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId               = 'ZTNA24827'
            TenantFilter         = $Tenant
            TestType             = 'ZeroTrustNetworkAccess'
            Status               = 'Failed'
            ResultMarkdown       = "❌ **Error**: $($_.Exception.Message)"
            Risk                 = 'Medium'
            Name                 = 'CA policies block unmanaged mobile apps'
            UserImpact           = 'Medium'
            ImplementationEffort = 'Medium'
            Category             = 'Application security'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA24827 failed: $($_.Exception.Message)" -sev Error
    }
}
