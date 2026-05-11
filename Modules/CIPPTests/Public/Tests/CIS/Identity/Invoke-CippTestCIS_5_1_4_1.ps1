function Invoke-CippTestCIS_5_1_4_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.4.1) - Ability to join devices to Entra SHALL be restricted
    #>
    param($Tenant)

    try {
        $DRP = Get-CIPPTestData -TenantFilter $Tenant -Type 'DeviceRegistrationPolicy'

        if (-not $DRP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DeviceRegistrationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Ability to join devices to Entra is restricted' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
            return
        }

        $Cfg = $DRP | Select-Object -First 1
        $JoinType = $Cfg.azureADJoin.allowedToJoin.'@odata.type'

        if ($JoinType -in @('#microsoft.graph.enumeratedDeviceRegistrationMembership', '#microsoft.graph.noDeviceRegistrationMembership')) {
            $Status = 'Passed'
            $Result = "Entra device join is restricted (allowedToJoin type: $JoinType)."
        } else {
            $Status = 'Failed'
            $Result = "Entra device join is open to All users (allowedToJoin type: $JoinType). Restrict to Selected or None."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Ability to join devices to Entra is restricted' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Ability to join devices to Entra is restricted' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Device Management'
    }
}
