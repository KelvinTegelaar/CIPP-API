function Invoke-CippTestCIS_2_1_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (2.1.7) - An anti-phishing policy SHALL be created
    #>
    param($Tenant)

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'CIS_2_1_7' -TenantFilter $Tenant -Preset DefenderForOffice365 -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_7' -TestType 'Identity' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender for Office 365 (ATP). Required capabilities: ATP_ENTERPRISE, ATP_ENTERPRISE_GOV, THREAT_INTELLIGENCE, THREAT_INTELLIGENCE_GOV.' -Risk 'High' -Name 'An anti-phishing policy has been created' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
            return
        }

        $AntiPhish = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $AntiPhish) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoAntiPhishPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'An anti-phishing policy has been created' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
            return
        }

        $AntiPhishRules = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishRules'

        # Get-AntiPhishPolicy only populates Enabled for the built-in default policy; a custom policy's
        # active state lives on its anti-phish rule's State, joined by AntiPhishPolicy name (mirrors
        # Invoke-CIPPStandardAntiPhishPolicy / Invoke-ListAntiPhishingFilters).
        $Compliant = $AntiPhish | Where-Object {
            $Policy = $_
            $RuleEnabled = [bool]($AntiPhishRules | Where-Object { $_.AntiPhishPolicy -eq $Policy.Name -and $_.State -eq 'Enabled' })
            ($Policy.Enabled -eq $true -or $RuleEnabled) -and
            $Policy.PhishThresholdLevel -ge 2 -and
            $Policy.EnableMailboxIntelligenceProtection -eq $true -and
            $Policy.EnableMailboxIntelligence -eq $true -and
            $Policy.EnableSpoofIntelligence -eq $true -and
            $Policy.TargetedUserProtectionAction -in @('Quarantine', 'MoveToJmf') -and
            $Policy.MailboxIntelligenceProtectionAction -in @('Quarantine', 'MoveToJmf') -and
            $Policy.TargetedDomainProtectionAction -in @('Quarantine', 'MoveToJmf') -and
            $Policy.AuthenticationFailAction -in @('Quarantine', 'MoveToJmf') -and
            $Policy.EnableFirstContactSafetyTips -eq $true -and
            $Policy.EnableSimilarUsersSafetyTips -eq $true -and
            $Policy.EnableSimilarDomainsSafetyTips -eq $true -and
            $Policy.EnableUnusualCharactersSafetyTips -eq $true
        }

        if ($Compliant) {
            $Status = 'Passed'
            $Result = "$($Compliant.Count) anti-phishing policy/policies meet CIS L2 requirements:`n`n"
            $Result += ($Compliant | ForEach-Object { "- $($_.Name)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No anti-phishing policy meets every CIS requirement (PhishThreshold>=2, all impersonation/intelligence/safety tips on, quarantine actions configured).'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_7' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'An anti-phishing policy has been created' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_7' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'An anti-phishing policy has been created' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
    }
}
