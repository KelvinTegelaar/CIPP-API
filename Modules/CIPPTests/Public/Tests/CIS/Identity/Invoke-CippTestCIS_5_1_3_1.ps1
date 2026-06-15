function Invoke-CippTestCIS_5_1_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.3.1) - Users SHALL NOT be able to create security groups
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Users cannot create security groups' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Management'
            return
        }

        $Cfg = $Auth | Select-Object -First 1

        if ($Cfg.defaultUserRolePermissions.allowedToCreateSecurityGroups -eq $false) {
            $Status = 'Passed'
            $Result = 'Users cannot create security groups (allowedToCreateSecurityGroups: false).'
        } else {
            $Status = 'Failed'
            $Result = "Users can create security groups (allowedToCreateSecurityGroups: $($Cfg.defaultUserRolePermissions.allowedToCreateSecurityGroups))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Users cannot create security groups' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Users cannot create security groups' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Group Management'
    }
}
