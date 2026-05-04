function Invoke-CippTestCIS_2_1_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (2.1.7) - An anti-phishing policy SHALL be created
    #>
    param($Tenant)

    try {
        $AntiPhish = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoAntiPhishPolicies'

        if (-not $AntiPhish) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_2_1_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoAntiPhishPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'An anti-phishing policy has been created' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Email Protection'
            return
        }

        $Compliant = $AntiPhish | Where-Object {
            $_.Enabled -eq $true -and
            $_.PhishThresholdLevel -ge 2 -and
            $_.EnableMailboxIntelligenceProtection -eq $true -and
            $_.EnableMailboxIntelligence -eq $true -and
            $_.EnableSpoofIntelligence -eq $true -and
            $_.TargetedUserProtectionAction -in @('Quarantine', 'MoveToJmf') -and
            $_.MailboxIntelligenceProtectionAction -in @('Quarantine', 'MoveToJmf') -and
            $_.TargetedDomainProtectionAction -in @('Quarantine', 'MoveToJmf') -and
            $_.AuthenticationFailAction -in @('Quarantine', 'MoveToJmf') -and
            $_.EnableFirstContactSafetyTips -eq $true -and
            $_.EnableSimilarUsersSafetyTips -eq $true -and
            $_.EnableSimilarDomainsSafetyTips -eq $true -and
            $_.EnableUnusualCharactersSafetyTips -eq $true
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
