function Invoke-CippTestZTNA21845 {
    <#
    .SYNOPSIS
    Temporary access pass is enabled
    #>
    param($Tenant)

    $TestId = 'ZTNA21845'
    #Tested
    try {
        # Get Temporary Access Pass configuration
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        $TAPConfig = $AuthMethodsPolicy.authenticationMethodConfigurations.Where({ $_.id -eq 'TemporaryAccessPass' })

        if (-not $TAPConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        # Check if TAP is disabled
        if ($TAPConfig.state -ne 'enabled') {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown '❌ Temporary Access Pass is disabled in the tenant.' -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $TAPEnabled = $TAPConfig.state -eq 'enabled'
        $TargetsAllUsers = $TAPConfig.includeTargets.Where({ $_.id -eq 'all_users' })
        $CALicensed = Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog

        $HasConditionalAccessEnforcement = $false
        $TAPSupportedInAuthStrength = $false
        if ($CALicensed) {
            $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
            $SecurityInfoPolicies = $CAPolicies.Where({
                $_.state -eq 'enabled' -and
                $_.conditions.applications.includeUserActions -contains 'urn:user:registersecurityinfo' -and
                $null -ne $_.grantControls.authenticationStrength
            })
            $HasConditionalAccessEnforcement = $SecurityInfoPolicies.Count -gt 0

            $TAPStrengthIds = @(@(Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationStrengths').Where({
                        $_.allowedCombinations -contains 'temporaryAccessPassOneTime' -or $_.allowedCombinations -contains 'temporaryAccessPassMultiUse'
                    }).id)
            $TAPSupportedInAuthStrength = $SecurityInfoPolicies.Where({ $TAPStrengthIds -contains $_.grantControls.authenticationStrength.id }).Count -gt 0
        }

        # Determine pass/fail status
        $Passed = 'Failed'
        if (-not $CALicensed -and $TAPEnabled -and $TargetsAllUsers) {
            $Passed = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new('Temporary Access Pass is enabled and targets all users. Conditional Access enforcement was not evaluated because the tenant is not licensed for Conditional Access.')
        } elseif ($TAPEnabled -and $TargetsAllUsers -and $HasConditionalAccessEnforcement -and $TAPSupportedInAuthStrength) {
            $Passed = 'Passed'
            $ResultMarkdown = [System.Text.StringBuilder]::new('Temporary Access Pass is enabled, targeting all users, and enforced with conditional access policies.')
        } elseif ($TAPEnabled -and $TargetsAllUsers -and $HasConditionalAccessEnforcement -and -not $TAPSupportedInAuthStrength) {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Temporary Access Pass is enabled but authentication strength policies don't include TAP methods.")
        } elseif ($TAPEnabled -and $TargetsAllUsers -and -not $HasConditionalAccessEnforcement) {
            $ResultMarkdown = [System.Text.StringBuilder]::new('Temporary Access Pass is enabled but no conditional access enforcement for security info registration found. Consider adding conditional access policies for stronger security.')
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new('Temporary Access Pass is not properly configured or does not target all users.')
        }

        $null = $ResultMarkdown.Append("`n`n**Configuration summary**`n`n")

        $TAPStatus = if ($TAPConfig.state -eq 'enabled') { 'Enabled ✅' } else { 'Disabled ❌' }
        $null = $ResultMarkdown.Append("[Temporary Access Pass](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods/fromNav/Identity): $TAPStatus`n`n")

        $CAStatus = if (-not $CALicensed) { 'Not applicable (requires Microsoft Entra ID P1)' } elseif ($HasConditionalAccessEnforcement) { 'Enabled ✅' } else { 'Not enabled ❌' }
        $null = $ResultMarkdown.Append("[Conditional Access policy for Security info registration](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies/fromNav/Identity): $CAStatus`n`n")

        $AuthStrengthStatus = if (-not $CALicensed) { 'Not applicable (requires Microsoft Entra ID P1)' } elseif ($TAPSupportedInAuthStrength) { 'Enabled ✅' } else { 'Not enabled ❌' }
        $null = $ResultMarkdown.Append("[Authentication strength policy for Temporary Access Pass](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/AuthenticationStrength.ReactView/fromNav/Identity): $AuthStrengthStatus`n")

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
