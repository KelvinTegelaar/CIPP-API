function Invoke-CippTestCIS_5_1_5_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.1.5.5) - Ensure new application passwords are system-generated
    #>
    param($Tenant)

    try {
        $Policy = Get-CIPPTestData -TenantFilter $Tenant -Type 'DefaultAppManagementPolicy'
        if (-not $Policy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'DefaultAppManagementPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'New application passwords are system-generated' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }
        $Cfg = $Policy | Select-Object -First 1

        $Restriction = $Cfg.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'customPasswordAddition' } | Select-Object -First 1

        if (-not $Cfg.isEnabled) {
            $Status = 'Failed'
            $Result = 'The default app management policy is not enabled (isEnabled is false). Custom application passwords are not blocked, so new passwords are not required to be system-generated.'
        } elseif (-not $Restriction) {
            $Status = 'Failed'
            $Result = 'No customPasswordAddition restriction is configured under the application restrictions. Custom application passwords are not blocked.'
        } elseif ($Restriction.state -ne 'enabled') {
            $Status = 'Failed'
            $Result = "The customPasswordAddition restriction is not enabled (state is '$($Restriction.state)'). Custom application passwords are not blocked, so new passwords are not required to be system-generated."
        } else {
            $Status = 'Passed'
            $Result = 'The default app management policy is enabled and the customPasswordAddition restriction is enabled. Custom passwords are blocked, so new application passwords must be system-generated.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'New application passwords are system-generated' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_5_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'New application passwords are system-generated' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
