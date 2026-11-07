function Invoke-CippTestZTNA35032 {
    <#
    .SYNOPSIS
    Adaptive Protection is enabled in data loss prevention policies
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35032'; TestType = 'Identity'; Name = 'Adaptive Protection is enabled in data loss prevention policies'; Risk = 'Medium'; UserImpact = 'Medium'; ImplementationEffort = 'Low'; Category = 'Data Loss Prevention (DLP)' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35032' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_ENTERPRISE') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online Plan 2. Required capability: EXCHANGE_S_ENTERPRISE.'
            return
        }
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35032' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'DLP rules are only collected for tenants licensed for Microsoft Purview Information Protection (RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2).'
            return
        }

        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpComplianceRules').Where({ $_ })
        if ($Rules.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'DlpComplianceRules' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $PortalLink = '[View DLP Policies in Microsoft Purview Portal](https://purview.microsoft.com/datalossprevention/policies)'
        $AdaptiveRules = @($Rules.Where({ $_.AdvancedRule -match 'SharedByIRMUserRisk' }))
        if ($AdaptiveRules.Count -eq 0) {
            Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "❌ No DLP policies use Adaptive Protection; policies do not have insider risk-based rules configured.`n`n$PortalLink"
            return
        }

        $RiskLevels = [ordered]@{ Elevated = 'FCB9FA93-6269-4ACF-A756-832E79B36A2A'; Moderate = '797C4446-5C73-484F-8E58-0CCA08D6DF6C'; Minor = '75A4318B-94A2-4323-BA42-2CA6DB29AAFE' }
        $LevelCounts = @{ Elevated = 0; Moderate = 0; Minor = 0 }
        $RuleRows = foreach ($Rule in $AdaptiveRules) {
            $Levels = foreach ($Level in $RiskLevels.Keys) {
                if ($Rule.AdvancedRule -match $RiskLevels[$Level]) { $LevelCounts[$Level]++; $Level }
            }
            $Enabled = if ($Rule.Disabled -eq $false) { '✅ Yes' } else { '❌ No' }
            $LevelText = if ($Levels) { @($Levels) -join ', ' } else { 'Unknown' }
            "| $($Rule.Name) | $($Rule.ParentPolicyName) | $Enabled | $LevelText |"
        }
        $PolicyCount = [System.Collections.Generic.HashSet[string]]::new([string[]]@(foreach ($Rule in $AdaptiveRules) { "$($Rule.ParentPolicyName)" })).Count

        $Result = @"
✅ Adaptive Protection is configured in DLP policies, enabling risk-based, behavior-driven data protection through insider risk integration.

### Adaptive Protection Summary

| Metric | Count |
| :----- | :---- |
| Total DLP Rules | $($Rules.Count) |
| Rules with Adaptive Protection | $($AdaptiveRules.Count) |
| Policies with Adaptive Protection | $PolicyCount |
| Rules with Elevated Risk Level | $($LevelCounts.Elevated) |
| Rules with Moderate Risk Level | $($LevelCounts.Moderate) |
| Rules with Minor Risk Level | $($LevelCounts.Minor) |

### DLP Rules with Adaptive Protection

| Rule Name | Parent Policy | Enabled | Risk Levels |
| :-------- | :------------ | :------ | :---------- |
$($RuleRows -join "`n")

$PortalLink
"@

        Add-CippTestResult @TestParams -Status 'Passed' -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
