function Invoke-CippTestCIS_7_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (7.2.1) - Modern authentication for SharePoint applications SHALL be required
    #>
    param($Tenant)

    try {
        $SPO = Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant'

        if (-not $SPO) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'SPOTenant cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Modern authentication for SharePoint applications is required' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $SPO | Select-Object -First 1

        if ($Cfg.LegacyAuthProtocolsEnabled -eq $false) {
            $Status = 'Passed'
            $Result = 'SharePoint legacy auth protocols are disabled (LegacyAuthProtocolsEnabled: false).'
        } else {
            $Status = 'Failed'
            $Result = "SharePoint legacy auth protocols are enabled (LegacyAuthProtocolsEnabled: $($Cfg.LegacyAuthProtocolsEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Modern authentication for SharePoint applications is required' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_7_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Modern authentication for SharePoint applications is required' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
