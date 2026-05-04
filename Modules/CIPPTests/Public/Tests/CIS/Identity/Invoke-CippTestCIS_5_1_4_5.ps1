function Invoke-CippTestCIS_5_1_4_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.4.5) - Local Administrator Password Solution (LAPS) SHALL be enabled
    #>
    param($Tenant)

    try {
        $DRP = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DRP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Local Administrator Password Solution is enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $Cfg = $DRP | Select-Object -First 1

        if ($Cfg.localAdminPassword.isEnabled -eq $true) {
            $Status = 'Passed'
            $Result = 'LAPS (cloud) is enabled at the tenant (localAdminPassword.isEnabled: true). Ensure an Intune Account Protection policy is also rotating local admin passwords on devices.'
        } else {
            $Status = 'Failed'
            $Result = "LAPS is disabled at the tenant (localAdminPassword.isEnabled: $($Cfg.localAdminPassword.isEnabled))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Local Administrator Password Solution is enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Local Administrator Password Solution is enabled' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
