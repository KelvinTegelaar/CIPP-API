function Invoke-CippTestCIS_5_1_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.2.2) - Third party integrated applications SHALL NOT be allowed
    #>
    param($Tenant)

    try {
        $Auth = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $Auth) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthorizationPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Third party integrated applications are not allowed' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $Cfg = $Auth | Select-Object -First 1

        if ($Cfg.defaultUserRolePermissions.allowedToCreateApps -eq $false) {
            $Status = 'Passed'
            $Result = 'Users cannot create app registrations (allowedToCreateApps: false).'
        } else {
            $Status = 'Failed'
            $Result = "Users can register applications (allowedToCreateApps: $($Cfg.defaultUserRolePermissions.allowedToCreateApps))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Third party integrated applications are not allowed' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Third party integrated applications are not allowed' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}
