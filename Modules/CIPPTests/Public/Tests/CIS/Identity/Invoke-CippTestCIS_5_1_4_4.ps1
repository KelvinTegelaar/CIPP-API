function Invoke-CippTestCIS_5_1_4_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.4.4) - Local administrator assignment SHALL be limited during Entra join
    #>
    param($Tenant)

    try {
        $DRP = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DRP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Local administrator assignment is limited during Entra join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
            return
        }

        $Cfg = $DRP | Select-Object -First 1
        $RegType = $Cfg.azureADJoin.localAdmins.registeringUsers.'@odata.type'

        if ($RegType -in @('#microsoft.graph.enumeratedDeviceRegistrationMembership', '#microsoft.graph.noDeviceRegistrationMembership')) {
            $Status = 'Passed'
            $Result = "Local admin assignment for registering users is restricted (type: $RegType)."
        } else {
            $Status = 'Failed'
            $Result = "Local admin assignment for registering users is set to All (type: $RegType). Restrict to Selected or None."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Local administrator assignment is limited during Entra join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Local administrator assignment is limited during Entra join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Privileged Access'
    }
}
