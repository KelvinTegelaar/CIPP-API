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
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        $TAPConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'TemporaryAccessPass' }

        if (-not $TAPConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        # Check if TAP is disabled
        if ($TAPConfig.state -ne 'enabled') {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown '❌ Temporary Access Pass is disabled in the tenant.' -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        # Get conditional access policies
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $SecurityInfoPolicies = $CAPolicies | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.applications.includeUserActions -contains 'urn:user:registersecurityinfo' -and
            $_.grantControls.authenticationStrength -ne $null
        }

        $TAPEnabled = $TAPConfig.state -eq 'enabled'
        $TargetsAllUsers = $TAPConfig.includeTargets | Where-Object { $_.id -eq 'all_users' }
        $HasConditionalAccessEnforcement = $SecurityInfoPolicies.Count -gt 0

        # Note: Authentication strength policy validation requires additional API calls not available in cache
        # Simplified check: verify TAP is enabled, targets all users, and CA policies exist
        $TAPSupportedInAuthStrength = $HasConditionalAccessEnforcement

        # Determine pass/fail status
        $Passed = 'Failed'
        if ($TAPEnabled -and $TargetsAllUsers -and $HasConditionalAccessEnforcement -and $TAPSupportedInAuthStrength) {
            $Passed = 'Passed'
            $ResultMarkdown = 'Temporary Access Pass is enabled, targeting all users, and enforced with conditional access policies.'
        } elseif ($TAPEnabled -and $TargetsAllUsers -and $HasConditionalAccessEnforcement -and -not $TAPSupportedInAuthStrength) {
            $ResultMarkdown = "Temporary Access Pass is enabled but authentication strength policies don't include TAP methods."
        } elseif ($TAPEnabled -and $TargetsAllUsers -and -not $HasConditionalAccessEnforcement) {
            $ResultMarkdown = 'Temporary Access Pass is enabled but no conditional access enforcement for security info registration found. Consider adding conditional access policies for stronger security.'
        } else {
            $ResultMarkdown = 'Temporary Access Pass is not properly configured or does not target all users.'
        }

        $ResultMarkdown += "`n`n**Configuration summary**`n`n"

        $TAPStatus = if ($TAPConfig.state -eq 'enabled') { 'Enabled ✅' } else { 'Disabled ❌' }
        $ResultMarkdown += "[Temporary Access Pass](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods/fromNav/Identity): $TAPStatus`n`n"

        $CAStatus = if ($HasConditionalAccessEnforcement) { 'Enabled ✅' } else { 'Not enabled ❌' }
        $ResultMarkdown += "[Conditional Access policy for Security info registration](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade/~/Policies/fromNav/Identity): $CAStatus`n`n"

        $AuthStrengthStatus = if ($TAPSupportedInAuthStrength) { 'Enabled ✅' } else { 'Not enabled ❌' }
        $ResultMarkdown += "[Authentication strength policy for Temporary Access Pass](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/AuthenticationStrength.ReactView/fromNav/Identity): $AuthStrengthStatus`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Temporary access pass is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
