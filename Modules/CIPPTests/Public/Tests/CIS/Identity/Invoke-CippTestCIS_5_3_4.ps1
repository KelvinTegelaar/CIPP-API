function Invoke-CippTestCIS_5_3_4 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.3.4) - Approval SHALL be required for Global Administrator role activation
    #>
    param($Tenant)

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'RoleManagementPolicies'
        $Roles = Get-CIPPTestData -TenantFilter $Tenant -Type 'Roles'

        if (-not $Policies -or -not $Roles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_4' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Required cache (RoleManagementPolicies or Roles) not found.' -Risk 'High' -Name 'Approval is required for Global Administrator role activation' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
            return
        }

        $GA = $Roles | Where-Object { $_.displayName -eq 'Global Administrator' } | Select-Object -First 1

        $GAPolicy = $Policies | Where-Object {
            $_.scopeId -eq '/' -and $_.scopeType -eq 'DirectoryRole' -and
            ($_.rules | Where-Object { $_.id -eq 'Approval_EndUser_Assignment' -and $_.setting.isApprovalRequired -eq $true })
        }

        if ($GAPolicy) {
            $Status = 'Passed'
            $Result = 'A PIM role management policy requires approval for activation. Verify it is scoped to Global Administrator.'
        } else {
            $Status = 'Failed'
            $Result = 'No PIM role management policy with isApprovalRequired = true was found for the GA scope. Configure approval in PIM role settings for Global Administrator.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_4' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Approval is required for Global Administrator role activation' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_3_4' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Approval is required for Global Administrator role activation' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Privileged Access'
    }
}
