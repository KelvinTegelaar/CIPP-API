function Invoke-CippTestZTNA41083 {
    <#
    .SYNOPSIS
    Step-up authentication is required upon risky in-session action
    #>
    param($Tenant)

    $TestId = 'ZTNA41083'
    $Name = 'Step-up authentication is required upon risky in-session action'
    $Common = @{ TenantFilter = $Tenant; TestId = $TestId; TestType = 'Identity'; Name = $Name; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Identity threat protection' }

    try {
        $HasP2 = Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset EntraP2 -SkipLog
        if (-not $HasP2 -or -not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -RequiredCapabilities 'ADALLOM_S_STANDALONE' -SkipLog)) {
            Add-CippTestResult @Common -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for both Microsoft Entra ID P2 and Microsoft Defender for Cloud Apps. Required capabilities: AAD_PREMIUM_P2, ADALLOM_S_STANDALONE.'
            return
        }

        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        if (-not $CAPolicies) {
            Add-CippTestResult @Common -Status 'Skipped' -ResultMarkdown 'No Conditional Access policies found in database. Data collection may not yet have completed.'
            return
        }

        $StrengthCombinations = @{}
        foreach ($Strength in @(Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationStrengths')) {
            if ($Strength.id) { $StrengthCombinations[$Strength.id] = @($Strength.allowedCombinations).Where({ -not [string]::IsNullOrWhiteSpace($_) }) }
        }
        $PhishingResistantStrengthId = '00000000-0000-0000-0000-000000000004'
        $PhishingResistantMethods = @('windowsHelloForBusiness', 'fido2', 'x509CertificateMultiFactor')

        $RiskPolicies = foreach ($Policy in $CAPolicies.Where({ $_.state -eq 'enabled' })) {
            $SignInRisk = @($Policy.conditions.signInRiskLevels).Where({ -not [string]::IsNullOrWhiteSpace($_) })
            $UserRisk = @($Policy.conditions.userRiskLevels).Where({ -not [string]::IsNullOrWhiteSpace($_) })
            if (-not ($SignInRisk -contains 'high' -or $UserRisk -contains 'high')) { continue }

            $Strength = $Policy.grantControls.authenticationStrength
            $HasStrength = -not [string]::IsNullOrWhiteSpace($Strength.id)
            $IsPhishingResistant = $false
            $IsUnresolved = $false
            if ($HasStrength) {
                if ($Strength.id -eq $PhishingResistantStrengthId) {
                    $IsPhishingResistant = $true
                } else {
                    $Combinations = @($Strength.allowedCombinations).Where({ -not [string]::IsNullOrWhiteSpace($_) })
                    if ($Combinations.Count -eq 0) { $Combinations = $StrengthCombinations[$Strength.id] }
                    if ($Combinations.Count -eq 0) {
                        $IsUnresolved = $true
                    } else {
                        $IsPhishingResistant = $Combinations.Where({ $PhishingResistantMethods -notcontains $_ }).Count -eq 0
                    }
                }
            }

            $BuiltInControls = @($Policy.grantControls.builtInControls).Where({ -not [string]::IsNullOrWhiteSpace($_) })
            # Any other grant control under OR lets the grant be satisfied without the authentication strength
            $AlternativeControls = @($Policy.grantControls.builtInControls; $Policy.grantControls.customAuthenticationFactors; $Policy.grantControls.termsOfUse).Where({ -not [string]::IsNullOrWhiteSpace($_) })
            $StrengthAlwaysRequired = $AlternativeControls.Count -eq 0 -or $Policy.grantControls.operator -eq 'AND'
            $IsMatch = $IsPhishingResistant -and $StrengthAlwaysRequired

            [PSCustomObject]@{
                DisplayName       = $Policy.displayName
                Id                = $Policy.id
                State             = $Policy.state
                SignInRisk        = if ($SignInRisk.Count -gt 0) { $SignInRisk -join ', ' } else { 'None' }
                UserRisk          = if ($UserRisk.Count -gt 0) { $UserRisk -join ', ' } else { 'None' }
                Strength          = if (-not $HasStrength) { 'None' } elseif ($Strength.displayName) { $Strength.displayName } else { $Strength.id }
                PhishingResistant = if ($IsUnresolved) { 'Unknown' } elseif ($IsPhishingResistant) { 'Yes' } else { 'No' }
                BuiltInControls   = if ($BuiltInControls.Count -gt 0) { $BuiltInControls -join ', ' } else { 'None' }
                RequiresMfa       = $BuiltInControls -contains 'mfa'
                IsPhishResistant  = $IsPhishingResistant
                IsUnresolved      = $IsUnresolved -and $StrengthAlwaysRequired
                IsMatch           = $IsMatch
            }
        }
        $RiskPolicies = @($RiskPolicies)

        if ($RiskPolicies.Where({ $_.IsMatch }).Count -gt 0) {
            $Status = 'Passed'
            $Result = '✅ At least one enabled Conditional Access policy combines an identity risk condition with a phishing-resistant authentication strength grant control, so a step-up challenge raised by a risky in-session action is enforced.'
        } elseif ($RiskPolicies.Where({ $_.IsUnresolved }).Count -gt 0) {
            $Status = 'Investigate'
            $Result = '⚠️ The allowed combinations of the custom authentication strength referenced by at least one identity risk policy could not be found, so the assessment cannot confirm whether step-up authentication is phishing-resistant.'
        } elseif ($RiskPolicies.Where({ -not $_.IsPhishResistant -and $_.RequiresMfa }).Count -gt 0) {
            $Status = 'Failed'
            $Result = '❌ Enabled Conditional Access policies use an identity risk condition but grant access with the multifactor authentication built-in control instead of a phishing-resistant authentication strength. Upgrade them to the built-in Phishing-resistant MFA strength, or to a custom strength whose allowed combinations only use FIDO2, certificate-based authentication (multifactor), or Windows Hello for Business.'
        } else {
            $Status = 'Failed'
            $Result = '❌ No enabled Conditional Access policy combines an identity risk condition with a phishing-resistant authentication strength grant control.'
        }

        $PortalUrl = 'https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/ConditionalAccessBlade'
        $Result = @(
            $Result
            ''
            "## [Microsoft Entra > Conditional Access > Policies]($PortalUrl)"
            if ($RiskPolicies.Count -gt 0) {
                ''
                '| Policy display name | State | Sign-in risk levels | User risk levels | Authentication strength | Phishing-resistant | Built-in controls | Status |'
                '| :------------------ | :---- | :------------------ | :--------------- | :---------------------- | :----------------- | :---------------- | :----- |'
                foreach ($Row in $RiskPolicies.Where({ $true }, 'First', 10)) {
                    $StatusDisplay = if ($Row.IsMatch) { '✅ Pass' } elseif ($Row.IsUnresolved) { '⚠️ Unknown' } else { '❌ Fail' }
                    "| [$($Row.DisplayName -replace '\|', '\|')](https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/$($Row.Id)) | $($Row.State) | $($Row.SignInRisk) | $($Row.UserRisk) | $($Row.Strength -replace '\|', '\|') | $($Row.PhishingResistant) | $($Row.BuiltInControls) | $StatusDisplay |"
                }
                if ($RiskPolicies.Count -gt 10) { "`n... and $($RiskPolicies.Count - 10) more. [Microsoft Entra > Conditional Access > Policies]($PortalUrl)" }
            }
        ) -join "`n"

        Add-CippTestResult @Common -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Common -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
