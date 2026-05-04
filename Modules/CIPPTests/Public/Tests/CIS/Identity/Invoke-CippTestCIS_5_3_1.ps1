function Invoke-CippTestCIS_5_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.3.1) - 'Privileged Identity Management' SHALL be used to manage roles
    #>
    param($Tenant)

    try {
        $Eligibility = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleEligibilitySchedules'
        $Active = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleAssignmentScheduleInstances'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'

        if (-not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Roles cache not found.' -Risk 'Medium' -Name "'Privileged Identity Management' is used to manage roles" -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Privileged Access'
            return
        }

        $PrivRoleIds = ($Roles | Where-Object { $_.isPrivileged -eq $true }).id
        $EligibleAssignmentsForPriv = $Eligibility | Where-Object { $_.roleDefinitionId -in $PrivRoleIds }

        if ($EligibleAssignmentsForPriv -and $EligibleAssignmentsForPriv.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($EligibleAssignmentsForPriv.Count) PIM eligible assignment(s) cover privileged roles. Confirm activation requires MFA, justification, and ticket # in the role settings."
        } else {
            $Status = 'Failed'
            $Result = 'No PIM eligible assignments found for privileged roles. PIM is not in use, or every privileged user holds an active assignment.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'Privileged Identity Management' is used to manage roles" -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'Privileged Identity Management' is used to manage roles" -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Privileged Access'
    }
}
