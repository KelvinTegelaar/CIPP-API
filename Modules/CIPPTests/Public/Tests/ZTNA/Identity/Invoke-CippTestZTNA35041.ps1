function Invoke-CippTestZTNA35041 {
    <#
    .SYNOPSIS
    Browser data loss prevention is enabled for AI apps via Edge for Business
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35041'; TestType = 'Identity'; Name = 'Browser data loss prevention is enabled for AI apps via Edge for Business'; Risk = 'Medium'; UserImpact = 'Medium'; ImplementationEffort = 'High'; Category = 'Data Security Posture Management' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35041' -TenantFilter $Tenant -RequiredCapabilities @('RMS_S_PREMIUM2') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection P2. Required capability: RMS_S_PREMIUM2.'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpCompliancePolicies').Where({ $_ })
        $Rules = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpComplianceRules').Where({ $_ })
        if ($Policies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'DlpCompliancePolicies' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $BrowserPolicies = @($Policies.Where({ $_.EnforcementPlanes -contains 'Browser' }))
        $RuleCounts = @{}
        foreach ($Policy in $BrowserPolicies) {
            $RuleCounts[$Policy.Name] = $Rules.Where({ $_.ParentPolicyName -eq $Policy.Name -or $_.Policy -eq $Policy.Identity }).Count
        }
        $BrowserRuleCount = 0
        foreach ($Count in $RuleCounts.Values) { $BrowserRuleCount = $BrowserRuleCount + $Count }
        $EnabledPolicies = @($BrowserPolicies.Where({ $_.Enabled -eq $true }))
        $EnabledWithRules = $EnabledPolicies.Where({ $RuleCounts[$_.Name] -gt 0 }).Count

        $Status, $Headline = if ($EnabledWithRules -ge 1) {
            'Passed', '✅ Browser Data Loss Prevention for AI Apps is configured and enabled via at least one active DLP policy with Browser enforcement, preventing sensitive data from being uploaded to or copied from unmanaged AI services through Edge for Business.'
        } else {
            'Failed', '❌ Browser DLP for AI apps is not configured. Either no Browser DLP policies exist, policies exist but have no rules, or all Browser DLP policies are disabled.'
        }

        $Lines = [System.Collections.Generic.List[string]]::new()
        $Lines.Add("$Headline`n")
        $Lines.Add("**Browser DLP Configuration Summary:**`n")
        $Lines.Add("* Browser DLP Policies Found: $($BrowserPolicies.Count)")
        $Lines.Add("* Browser DLP Policies Enabled: $($EnabledPolicies.Count)")
        $Lines.Add("* Enabled Policies with Rules: $EnabledWithRules")
        $Lines.Add("* Browser DLP Rules: $BrowserRuleCount`n")
        if ($BrowserPolicies.Count -gt 0) {
            $Lines.Add("## [Discovered Policies](https://purview.microsoft.com/datalossprevention/policies)`n")
            $Lines.Add('| Policy name | Enabled | Mode | Enforcement planes | Policy category | Created by | Creation time (UTC) | Rules count |')
            $Lines.Add('|:---|:---|:---|:---|:---|:---|:---|:---|')
            foreach ($Policy in $BrowserPolicies) {
                $Mode = if ($Policy.Mode) { $Policy.Mode } else { 'N/A' }
                $Category = if ($Policy.PolicyCategory) { $Policy.PolicyCategory } else { 'N/A' }
                $CreatedBy = if ($Policy.CreatedBy) { $Policy.CreatedBy } else { 'N/A' }
                $Created = if ($Policy.CreationTimeUtc) { ([datetime]$Policy.CreationTimeUtc).ToString('yyyy-MM-ddTHH:mm:ssZ') } else { 'N/A' }
                $Lines.Add("| $($Policy.Name) | $($Policy.Enabled -eq $true) | $Mode | $(@($Policy.EnforcementPlanes) -join ', ') | $Category | $CreatedBy | $Created | $($RuleCounts[$Policy.Name]) |")
            }
        }

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown ($Lines -join "`n")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
