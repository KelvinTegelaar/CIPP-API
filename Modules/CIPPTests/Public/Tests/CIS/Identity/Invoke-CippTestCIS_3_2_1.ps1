function Invoke-CippTestCIS_3_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (3.2.1) - DLP policies SHALL be enabled
    #>
    param($Tenant)

    try {
        $Dlp = Get-CIPPTestData -TenantFilter $Tenant -Type 'DlpCompliancePolicies'

        if (-not $Dlp) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DlpCompliancePolicies cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'DLP policies are enabled' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
            return
        }

        $Enabled = $Dlp | Where-Object { $_.Mode -eq 'Enable' -and $_.Enabled -eq $true }

        if ($Enabled.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($Enabled.Count) of $($Dlp.Count) DLP policy/policies are enabled and in Enforce mode:`n`n"
            $Result += ($Enabled | ForEach-Object { "- $($_.Name)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = "No DLP policies are enabled in Enforce mode. $(($Dlp | Measure-Object).Count) policy/policies exist but are in test/disabled state."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'DLP policies are enabled' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_3_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'DLP policies are enabled' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Data Protection'
    }
}
