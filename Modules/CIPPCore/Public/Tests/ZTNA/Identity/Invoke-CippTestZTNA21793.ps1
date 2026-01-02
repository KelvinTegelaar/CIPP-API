function Invoke-CippTestZTNA21793 {
    <#
    .SYNOPSIS
    Tenant restrictions v2 policy is configured
    #>
    param($Tenant)
    #tested
    try {
        $CrossTenantPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'CrossTenantAccessPolicy'

        if (-not $CrossTenantPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21793' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Tenant restrictions v2 policy is configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $TenantRestrictions = $CrossTenantPolicy.tenantRestrictions

        if (-not $TenantRestrictions) {
            $Status = 'Failed'
            $Result = 'Tenant Restrictions v2 policy is not configured'
        } else {
            $UsersBlocked = $TenantRestrictions.usersAndGroups.accessType -eq 'blocked' -and
            $TenantRestrictions.usersAndGroups.targets[0].target -eq 'AllUsers'

            $AppsBlocked = $TenantRestrictions.applications.accessType -eq 'blocked' -and
            $TenantRestrictions.applications.targets[0].target -eq 'AllApplications'

            if ($UsersBlocked -and $AppsBlocked) {
                $Status = 'Passed'
                $Result = 'Tenant Restrictions v2 policy is properly configured'
            } else {
                $Status = 'Failed'
                $Result = 'Tenant Restrictions v2 policy is configured but not properly restricting all users and applications'
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21793' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Tenant restrictions v2 policy is configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21793' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Tenant restrictions v2 policy is configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
