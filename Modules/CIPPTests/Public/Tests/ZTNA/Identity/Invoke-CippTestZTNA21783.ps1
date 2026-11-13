function Invoke-CippTestZTNA21783 {
    <#
    .SYNOPSIS
    Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods
    #>
    param($Tenant)
    #tested
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA21783' -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Conditional Access. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $Roles = Get-CippDbRole -TenantFilter $Tenant -IncludePrivilegedRoles

        if (-not $CAPolicies -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        # Get-CippDbRole -IncludePrivilegedRoles already returns the privileged built-in directory roles.
        $PrivilegedRoles = @($Roles)

        if (-not $PrivilegedRoles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'No privileged built-in roles found in tenant' -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
            return
        }

        $PhishResistantMethods = @('windowsHelloForBusiness', 'fido2', 'x509CertificateMultiFactor')

        # Only authentication strengths whose every allowed combination is phishing resistant count
        $PhishResistantPolicies = $CAPolicies.Where({
                $Policy = $_
                $Combinations = @(foreach ($Combination in $Policy.grantControls.authenticationStrength.allowedCombinations) { $Combination })
                $Policy.state -eq 'enabled' -and
                $Policy.conditions.users.includeRoles -and
                $Combinations.Count -gt 0 -and
                $Combinations.Where({ $PhishResistantMethods -notcontains $_ }).Count -eq 0
            })

        $CoveredRoleIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($RoleId in $PhishResistantPolicies.conditions.users.includeRoles) { [void]$CoveredRoleIds.Add([string]$RoleId) }

        # Conditional Access includeRoles reference role template IDs, not directory role instance IDs.
        $ProtectedRoles = @($PrivilegedRoles.Where({ $CoveredRoleIds.Contains([string]$_.roleTemplateId) }))
        $UnprotectedRoles = @($PrivilegedRoles.Where({ -not $CoveredRoleIds.Contains([string]$_.roleTemplateId) }))

        $Status = if ($UnprotectedRoles.Count -eq 0) { 'Passed' } else { 'Failed' }
        $Result = [System.Text.StringBuilder]::new()
        if ($Status -eq 'Passed') {
            $null = $Result.Append("All privileged built-in roles are protected by Conditional Access policies that enforce phishing-resistant authentication.`n`n")
        } else {
            $null = $Result.Append("Some privileged built-in roles don't have Conditional Access policies to enforce phishing-resistant authentication.`n`n")
        }

        $null = $Result.Append("## Conditional Access policies with phishing resistant authentication policies`n`n")
        if ($PhishResistantPolicies.Count -eq 0) {
            $null = $Result.Append("No enabled Conditional Access policies targeting roles found with phishing resistant authentication strength policies.`n`n")
        } else {
            $null = $Result.Append("Found $($PhishResistantPolicies.Count) phishing resistant Conditional Access policies.`n`n")
            foreach ($Policy in $PhishResistantPolicies) {
                $null = $Result.Append("- [$($Policy.displayName)](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Policy.id)) ($($Policy.grantControls.authenticationStrength.displayName))`n")
            }
            $null = $Result.Append("`n")
        }

        $null = $Result.Append("## Privileged roles`n`n")
        if ($ProtectedRoles.Count -eq 0) {
            $null = $Result.Append("Privileged built-in roles are not being protected by phishing resistant authentication.`n`n")
        } elseif ($UnprotectedRoles.Count -eq 0) {
            $null = $Result.Append("All $($ProtectedRoles.Count) privileged built-in roles are protected by phishing resistant authentication.`n`n")
        } else {
            $null = $Result.Append("Found $($ProtectedRoles.Count) of $($PrivilegedRoles.Count) privileged built-in roles protected by phishing resistant authentication.`n`n")
        }
        $null = $Result.Append("| Role name | Phishing resistance enforced |`n")
        $null = $Result.Append("| :--- | :---: |`n")
        foreach ($Role in ($ProtectedRoles | Sort-Object displayName)) { $null = $Result.Append("| $($Role.displayName) | ✅ |`n") }
        foreach ($Role in ($UnprotectedRoles | Sort-Object displayName)) { $null = $Result.Append("| $($Role.displayName) | ❌ |`n") }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21783' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Privileged Microsoft Entra built-in roles are targeted with Conditional Access policies to enforce phishing-resistant methods' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Access Control'
    }
}
