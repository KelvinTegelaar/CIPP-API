function Invoke-CippTestCIS_5_1_6_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.6.3) - Guest user invitations SHALL be limited to the Guest Inviter role
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Guest user invitations are limited to the Guest Inviter role' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $Cfg = $Auth | Select-Object -First 1
        $Allow = $Cfg.allowInvitesFrom

        if ($Allow -eq 'adminsAndGuestInviters') {
            $Status = 'Passed'
            $Result = "Guest invitations restricted to Admins and Guest Inviters (allowInvitesFrom: $Allow)."
        } else {
            $Status = 'Failed'
            $Result = "Guest invitations are not limited to the Guest Inviter role (allowInvitesFrom: $Allow). Set to 'adminsAndGuestInviters'."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Guest user invitations are limited to the Guest Inviter role' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_6_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guest user invitations are limited to the Guest Inviter role' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
