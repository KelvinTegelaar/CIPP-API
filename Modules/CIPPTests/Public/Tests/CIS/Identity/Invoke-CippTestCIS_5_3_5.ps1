function Invoke-CippTestCIS_5_3_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.3.5) - Approval SHALL be required for Privileged Role Administrator activation
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleManagementPolicies'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'

        if (-not $Policies -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (RoleManagementPolicies or Roles) not found.' -Risk 'High' -Name 'Approval is required for Privileged Role Administrator activation' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $PRA = $Roles | Where-Object { $_.displayName -eq 'Privileged Role Administrator' } | Select-Object -First 1

        $ApprovalPolicy = $Policies | Where-Object {
            $_.scopeId -eq '/' -and $_.scopeType -eq 'DirectoryRole' -and
            ($_.rules | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' -and $_.setting.isApprovalRequired -eq $true })
        }

        if ($ApprovalPolicy) {
            $Status = 'Passed'
            $Result = 'A PIM role management policy requires approval for activation. Verify it is scoped to Privileged Role Administrator.'
        } else {
            $Status = 'Failed'
            $Result = 'No PIM role management policy with isApprovalRequired = true was found. Configure approval in PIM role settings for Privileged Role Administrator.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Approval is required for Privileged Role Administrator activation' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Approval is required for Privileged Role Administrator activation' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
