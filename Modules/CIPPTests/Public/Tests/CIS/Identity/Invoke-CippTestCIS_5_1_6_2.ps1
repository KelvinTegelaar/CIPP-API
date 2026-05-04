function Invoke-CippTestCIS_5_1_6_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.6.2) - Guest user access SHALL be restricted
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Guest user access is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $Auth | Select-Object -First 1

        # Restricted guest user role template ID
        $RestrictedGuest = '2af84b1e-32c8-42b7-82bc-daa82404023b'

        if ($Cfg.guestUserRoleId -eq $RestrictedGuest) {
            $Status = 'Passed'
            $Result = 'Guest users are assigned the most restricted role (Restricted Guest).'
        } else {
            $Status = 'Failed'
            $Result = "Guest users are not on the Restricted Guest role (current guestUserRoleId: $($Cfg.guestUserRoleId), expected: $RestrictedGuest)."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Guest user access is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guest user access is restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
