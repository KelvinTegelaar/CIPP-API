function Invoke-CippTestZTNA21872 {
    <#
    .SYNOPSIS
    Require multifactor authentication for device join and device registration using user action
    #>
    param($Tenant)

    $TestId = 'ZTNA21872'
    #Tested
    try {
        # Get conditional access policies and device registration policy from cache
        $CAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $DeviceRegistrationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Require multifactor authentication for device join and device registration using user action' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        if (-not $DeviceRegistrationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Require multifactor authentication for device join and device registration using user action' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        $MfaRequiredInDeviceSettings = $DeviceRegistrationPolicy.multiFactorAuthConfiguration -eq 'required'

        # Filter for enabled device registration CA policies
        $DeviceRegistrationPolicies = $CAPolicies | Where-Object {
            ($_.state -eq 'enabled') -and
            ($_.conditions.applications.includeUserActions -eq 'urn:user:registerdevice')
        }

        # Check each policy to see if it properly requires MFA
        $ValidPolicies = [System.Collections.Generic.List[object]]::new()
        foreach ($Policy in $DeviceRegistrationPolicies) {
            $RequiresMfa = $false

            # Check if the policy directly requires MFA
            if ($Policy.grantControls.builtInControls -contains 'mfa') {
                $RequiresMfa = $true
            }

            # Check if the policy uses any authentication strength
            if ($null -ne $Policy.grantControls.authenticationStrength) {
                $RequiresMfa = $true
            }

            # If the policy requires MFA, add it to valid policies
            if ($RequiresMfa) {
                $ValidPolicies.Add($Policy)
            }
        }

        # Determine pass/fail conditions
        if ($MfaRequiredInDeviceSettings) {
            $Passed = 'Failed'
            $ResultMarkdown = "❌ **MFA is configured incorrectly.** Device Settings has 'Require Multi-Factor Authentication to register or join devices' set to Yes. According to best practices, this should be set to No, and MFA should be enforced through Conditional Access policies instead.`n`n"
        } elseif ($DeviceRegistrationPolicies.Count -eq 0) {
            $Passed = 'Failed'
            $ResultMarkdown = "❌ **No Conditional Access policies found** for device registration or device join. Create a policy that requires MFA for these user actions.`n`n"
        } elseif ($ValidPolicies.Count -eq 0) {
            $Passed = 'Failed'
            $ResultMarkdown = "❌ **Conditional Access policies found**, but they're not correctly configured. Policies should require MFA or appropriate authentication strength.`n`n"
        } else {
            $Passed = 'Passed'
            $ResultMarkdown = "✅ **Properly configured Conditional Access policies found** that require MFA for device registration/join actions.`n`n"
        }

        # Add device settings information
        $ResultMarkdown += "## Device Settings Configuration`n`n"
        $ResultMarkdown += "| Setting | Value | Recommended Value | Status |`n"
        $ResultMarkdown += "| :------ | :---- | :---------------- | :----- |`n"

        $DeviceSettingStatus = if ($MfaRequiredInDeviceSettings) { '❌ Should be set to No' } else { '✅ Correctly configured' }
        $DeviceSettingValue = if ($MfaRequiredInDeviceSettings) { 'Yes' } else { 'No' }
        $ResultMarkdown += "| Require Multi-Factor Authentication to register or join devices | $DeviceSettingValue | No | $DeviceSettingStatus |`n"

        # Add policies information if any found
        if ($DeviceRegistrationPolicies.Count -gt 0) {
            $ResultMarkdown += "`n## Device Registration/Join Conditional Access Policies`n`n"
            $ResultMarkdown += "| Policy Name | State | Requires MFA | Status |`n"
            $ResultMarkdown += "| :---------- | :---- | :----------- | :----- |`n"

            foreach ($Policy in $DeviceRegistrationPolicies) {
                $PolicyName = $Policy.displayName
                $PolicyState = $Policy.state
                $PolicyLink = "https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)"
                $PolicyNameLink = "[$PolicyName]($PolicyLink)"

                # Check if this policy is properly configured
                $IsValid = $Policy -in $ValidPolicies
                $RequiresMfaText = if ($IsValid) { 'Yes' } else { 'No' }
                $StatusText = if ($IsValid) { '✅ Properly configured' } else { '❌ Incorrectly configured' }

                $ResultMarkdown += "| $PolicyNameLink | $PolicyState | $RequiresMfaText | $StatusText |`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Require multifactor authentication for device join and device registration using user action' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Require multifactor authentication for device join and device registration using user action' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Access control'
    }
}
