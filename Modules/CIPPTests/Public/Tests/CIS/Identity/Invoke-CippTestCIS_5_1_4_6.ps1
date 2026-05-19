function Invoke-CippTestCIS_5_1_4_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.4.6) - Users SHALL be restricted from recovering BitLocker keys
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Users are restricted from recovering BitLocker keys' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
            return
        }

        $Cfg = $Auth | Select-Object -First 1

        if ($Cfg.defaultUserRolePermissions.allowedToReadBitLockerKeysForOwnedDevice -eq $false) {
            $Status = 'Passed'
            $Result = 'Users cannot self-service recover BitLocker keys (allowedToReadBitLockerKeysForOwnedDevice: false).'
        } else {
            $Status = 'Failed'
            $Result = "Users can self-service recover BitLocker keys (allowedToReadBitLockerKeysForOwnedDevice: $($Cfg.defaultUserRolePermissions.allowedToReadBitLockerKeysForOwnedDevice))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users are restricted from recovering BitLocker keys' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_4_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users are restricted from recovering BitLocker keys' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Data Protection'
    }
}
