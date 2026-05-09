function Invoke-CippTestCIS_5_1_5_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.5.2) - The admin consent workflow SHALL be enabled
    #>
    param($Tenant)

    try {
        $Policy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AdminConsentRequestPolicy'

        if (-not $Policy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AdminConsentRequestPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'The admin consent workflow is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $Cfg = $Policy | Select-Object -First 1

        if ($Cfg.isEnabled -eq $true -and $Cfg.reviewers -and $Cfg.reviewers.Count -gt 0) {
            $Status = 'Passed'
            $Result = "Admin consent workflow is enabled with $($Cfg.reviewers.Count) reviewer(s)."
        } elseif ($Cfg.isEnabled -eq $true) {
            $Status = 'Failed'
            $Result = 'Admin consent workflow is enabled but no reviewers are configured. Add at least one reviewer.'
        } else {
            $Status = 'Failed'
            $Result = "Admin consent workflow is disabled (isEnabled: $($Cfg.isEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'The admin consent workflow is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'The admin consent workflow is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}
