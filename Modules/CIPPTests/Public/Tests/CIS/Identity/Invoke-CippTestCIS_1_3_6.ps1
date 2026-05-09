function Invoke-CippTestCIS_1_3_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.6) - Customer Lockbox SHALL be enabled
    #>
    param($Tenant)

    try {
        $OrgConfig = Get-CIPPTestData -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Customer Lockbox is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Cfg = $OrgConfig | Select-Object -First 1

        if ($Cfg.CustomerLockBoxEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'Customer Lockbox is enabled.'
        } else {
            $Status = 'Failed'
            $Result = "Customer Lockbox is disabled (CustomerLockBoxEnabled: $($Cfg.CustomerLockBoxEnabled)). Requires E5 or Compliance add-on."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Customer Lockbox is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Customer Lockbox is enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
