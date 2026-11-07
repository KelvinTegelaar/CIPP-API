function Invoke-CippTestZTNA35030 {
    <#
    .SYNOPSIS
    Data loss prevention policies are enabled
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35030'; TestType = 'Identity'; Name = 'Data loss prevention policies are enabled'; Risk = 'High'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Data Loss Prevention (DLP)' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35030' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_ENTERPRISE') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Exchange Online Plan 2. Required capability: EXCHANGE_S_ENTERPRISE.'
            return
        }
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35030' -TenantFilter $Tenant -Preset Compliance -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'DLP policies are only collected for tenants licensed for Microsoft Purview Information Protection (RMS_S_PREMIUM, RMS_S_PREMIUM2, MIP_S_CLP1, MIP_S_CLP2).'
            return
        }

        $Policies = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpCompliancePolicies').Where({ $_ })
        if ($Policies.Count -eq 0 -and -not (Get-CIPPDbItem -TenantFilter $Tenant -Type 'DlpCompliancePolicies' -CountsOnly)) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $EnabledCount = $Policies.Where({ $_.Enabled -eq $true }).Count
        $Lines = [System.Collections.Generic.List[string]]::new()
        if ($EnabledCount -ge 1) {
            $Status = 'Passed'
            $Lines.Add("✅ One or more DLP policies are enabled and configured, providing automated protection against sensitive data disclosure.`n")
        } else {
            $Status = 'Failed'
            $Lines.Add("❌ No DLP policies are enabled or no DLP policies exist in the organization.`n")
        }
        $Lines.Add("## Data Loss Prevention Policy Summary`n")
        $Lines.Add("**Total DLP Policies:** $($Policies.Count)`n")
        $Lines.Add("**Enabled Policies:** $EnabledCount`n")
        if ($Policies.Count -gt 0) {
            $Lines.Add("### DLP Policies Configuration`n")
            $Lines.Add('| Policy Name | Enabled Status | Created Date | Last Modified Date |')
            $Lines.Add('| :--- | :--- | :--- | :--- |')
            foreach ($Policy in $Policies) {
                $Enabled = if ($Policy.Enabled -eq $true) { '✅ Yes' } else { '❌ No' }
                $Created = if ($Policy.WhenCreatedUTC) { ([datetime]$Policy.WhenCreatedUTC).ToString('yyyy-MM-dd') } else { 'N/A' }
                $Modified = if ($Policy.WhenChangedUTC) { ([datetime]$Policy.WhenChangedUTC).ToString('yyyy-MM-dd') } else { 'N/A' }
                $Lines.Add("| $($Policy.Name) | $Enabled | $Created | $Modified |")
            }
            $Lines.Add('')
        }
        $Lines.Add('[View DLP Policies in Microsoft Purview Portal](https://purview.microsoft.com/datalossprevention/policies)')

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown ($Lines -join "`n")
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
