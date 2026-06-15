function Invoke-CippTestCIS_5_1_5_3 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.5.3) - Ensure password addition is blocked for applications
    #>
    param($Tenant)

    try {
        $Policy = Get-CIPPTestData -TenantFilter $Tenant -Type 'DefaultAppManagementPolicy'
        if (-not $Policy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_3' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DefaultAppManagementPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'Password addition is blocked for applications' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }
        $Cfg = $Policy | Select-Object -First 1

        $Restriction = $Cfg.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordAddition' } | Select-Object -First 1

        if (-not $Cfg.isEnabled) {
            $Status = 'Failed'
            $Result = 'The default app management policy is not enabled (isEnabled is false). Password addition is not blocked for applications.'
        } elseif (-not $Restriction) {
            $Status = 'Failed'
            $Result = 'No passwordAddition restriction is configured under the application restrictions. Password addition is not blocked.'
        } elseif ($Restriction.state -ne 'enabled') {
            $Status = 'Failed'
            $Result = "The passwordAddition restriction is not enabled (state is '$($Restriction.state)'). Password addition is not blocked for applications."
        } else {
            $Status = 'Passed'
            $Result = 'The default app management policy is enabled and the passwordAddition restriction is enabled. Password addition is blocked for applications.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_3' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Password addition is blocked for applications' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_3' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Password addition is blocked for applications' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
