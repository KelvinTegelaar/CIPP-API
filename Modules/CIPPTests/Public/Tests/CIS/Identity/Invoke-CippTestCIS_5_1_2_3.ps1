function Invoke-CippTestCIS_5_1_2_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.2.3) - 'Restrict non-admin users from creating tenants' SHALL be 'Yes'
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'Restrict non-admin users from creating tenants' is set to Yes" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
            return
        }

        $Cfg = $Auth | Select-Object -First 1

        if ($Cfg.defaultUserRolePermissions.allowedToCreateTenants -eq $false) {
            $Status = 'Passed'
            $Result = 'Non-admin users cannot create new tenants (allowedToCreateTenants: false).'
        } else {
            $Status = 'Failed'
            $Result = "Non-admin users can create new tenants (allowedToCreateTenants: $($Cfg.defaultUserRolePermissions.allowedToCreateTenants))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'Restrict non-admin users from creating tenants' is set to Yes" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'Restrict non-admin users from creating tenants' is set to Yes" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Identity'
    }
}
