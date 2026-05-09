function Invoke-CippTestCIS_5_1_4_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.4.3) - GA role SHALL NOT be added as local administrator during Entra join
    #>
    param($Tenant)

    try {
        $DRP = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DRP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'GA role is not added as local administrator during Entra join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $Cfg = $DRP | Select-Object -First 1
        $EnableGA = [bool]$Cfg.azureADJoin.localAdmins.enableGlobalAdmins

        if (-not $EnableGA) {
            $Status = 'Passed'
            $Result = 'Global Administrators are not granted local admin during Entra join (enableGlobalAdmins: false).'
        } else {
            $Status = 'Failed'
            $Result = "Global Administrators are granted local admin during Entra join (enableGlobalAdmins: true). Use the Microsoft Entra Joined Device Local Administrator role instead."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'GA role is not added as local administrator during Entra join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'GA role is not added as local administrator during Entra join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
    }
}
