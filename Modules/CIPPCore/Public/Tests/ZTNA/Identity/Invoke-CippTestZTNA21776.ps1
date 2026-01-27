function Invoke-CippTestZTNA21776 {
    <#
    .SYNOPSIS
    User consent settings are restricted
    #>
    param($Tenant)
    #tested
    try {
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'
        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21776' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'User consent settings are restricted' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $Matched = $AuthPolicy | Where-Object { $_.defaultUserRolePermissions.permissionGrantPoliciesAssigned -match '^ManagePermissionGrantsForSelf' }
        $NoMatch = $Matched.Count -eq 0
        $LowImpact = $Matched.defaultUserRolePermissions.permissionGrantPoliciesAssigned -contains 'managePermissionGrantsForSelf.microsoft-user-default-low'

        if ($NoMatch -or $LowImpact) {
            $Status = 'Passed'
            $Result = if ($NoMatch) { 'User consent is disabled' } else { 'User consent restricted to verified publishers and low-impact permissions' }
        } else {
            $Status = 'Failed'
            $Result = 'Users can consent to any application'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21776' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'User consent settings are restricted' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21776' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'User consent settings are restricted' -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
