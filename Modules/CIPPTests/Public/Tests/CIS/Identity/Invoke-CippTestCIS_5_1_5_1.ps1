function Invoke-CippTestCIS_5_1_5_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.5.1) - User consent to apps accessing company data SHALL NOT be allowed
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'User consent to apps accessing company data on their behalf is not allowed' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $Cfg = $Auth | Select-Object -First 1
        $ConsentPolicies = $Cfg.defaultUserRolePermissions.permissionGrantPoliciesAssigned

        $RestrictedConsent = $ConsentPolicies -contains 'ManagePermissionGrantsForSelf.microsoft-user-default-low' -or
                             ($ConsentPolicies | Where-Object { $_ -like '*low*' })

        if (-not $ConsentPolicies -or $ConsentPolicies.Count -eq 0 -or ($ConsentPolicies -notcontains 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy')) {
            $Status = 'Passed'
            $Result = "User consent to apps is restricted. Permission grant policies: $($ConsentPolicies -join ', ')"
        } else {
            $Status = 'Failed'
            $Result = "User consent to apps is open (legacy policy assigned). Permission grant policies: $($ConsentPolicies -join ', ')"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'User consent to apps accessing company data on their behalf is not allowed' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'User consent to apps accessing company data on their behalf is not allowed' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}
