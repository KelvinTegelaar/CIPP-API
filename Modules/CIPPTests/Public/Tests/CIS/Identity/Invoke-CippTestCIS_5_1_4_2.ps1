function Invoke-CippTestCIS_5_1_4_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.4.2) - Maximum number of devices per user SHALL be limited
    #>
    param($Tenant)

    try {
        $DRP = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DRP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Maximum number of devices per user is limited' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device Management'
            return
        }

        $Cfg = $DRP | Select-Object -First 1
        $Quota = [int]$Cfg.userDeviceQuota

        if ($Quota -gt 0 -and $Quota -le 20) {
            $Status = 'Passed'
            $Result = "userDeviceQuota is set to $Quota (CIS recommends 20 or less)."
        } else {
            $Status = 'Failed'
            $Result = "userDeviceQuota is $Quota (CIS recommends 20 or less)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Maximum number of devices per user is limited' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Maximum number of devices per user is limited' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Device Management'
    }
}
