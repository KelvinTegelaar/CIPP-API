function Invoke-CippTestCIS_7_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.2) - SharePoint and OneDrive integration with Azure AD B2B SHALL be enabled
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'SharePoint and OneDrive integration with Azure AD B2B is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $SPO | Select-Object -First 1

        if ($Cfg.EnableAzureADB2BIntegration -eq $true) {
            $Status = 'Passed'
            $Result = 'SharePoint / OneDrive Entra B2B integration is enabled.'
        } else {
            $Status = 'Failed'
            $Result = "SharePoint / OneDrive Entra B2B integration is disabled (EnableAzureADB2BIntegration: $($Cfg.EnableAzureADB2BIntegration))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'SharePoint and OneDrive integration with Azure AD B2B is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'SharePoint and OneDrive integration with Azure AD B2B is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
