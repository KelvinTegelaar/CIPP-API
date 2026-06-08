function Invoke-CippTestCIS_3_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (3.2.3) - Ensure DLP policies are published for Copilot users
    #>
    param($Tenant)

    try {
        $Dlp = Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpCompliancePolicies'

        if (-not $Dlp) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DlpCompliancePolicies cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'DLP policies are published for Copilot users' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
            return
        }

        $CopilotDlp = $Dlp | Where-Object {
            $_.Mode -eq 'Enable' -and $_.Enabled -eq $true -and (
                $_.EnforcementPlanes -match 'CopilotExperiences' -or
                $_.Workload -match 'Copilot'
            )
        }

        if ($CopilotDlp.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($CopilotDlp.Count) DLP policy/policies cover Microsoft 365 Copilot:`n`n"
            $Result += ($CopilotDlp | ForEach-Object { "- $($_.Name)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled DLP policy currently covers Microsoft 365 Copilot. Add the Microsoft 365 Copilot and Copilot Chat location to at least one enforced DLP policy.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DLP policies are published for Copilot users' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DLP policies are published for Copilot users' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
    }
}
