function Invoke-CippTestZTNA21817 {
    <#
    .SYNOPSIS
    Global Administrator role activation triggers an approval workflow
    #>
    param($Tenant)

    try {
        $RoleManagementPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'RoleManagementPolicies'

        if (-not $RoleManagementPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21817' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Global Administrator role activation triggers an approval workflow' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $globalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'

        $globalAdminPolicy = $RoleManagementPolicies | Where-Object {
            $_.scopeId -eq '/' -and
            $_.scopeType -eq 'DirectoryRole' -and
            $_.roleDefinitionId -eq $globalAdminRoleId
        }

        $tableRows = ''
        $result = $false

        if ($globalAdminPolicy) {
            $approvalRule = $globalAdminPolicy.rules | Where-Object { $_.id -like '*Approval_EndUser_Assignment*' }

            if ($approvalRule -and $approvalRule.setting.isApprovalRequired -eq $true) {
                $approverCount = 0
                foreach ($stage in $approvalRule.setting.approvalStages) {
                    $approverCount = $approverCount + ($stage.primaryApprovers | Measure-Object).Count
                }

                if ($approverCount -gt 0) {
                    $result = $true
                    $testResultMarkdown = "✅ **Pass**: Approval required with $approverCount primary approver(s) configured.`n`n%TestResult%"
                    $primaryApprovers = ($approvalRule.setting.approvalStages[0].primaryApprovers.description -join ', ')
                    $escalationApprovers = ($approvalRule.setting.approvalStages[0].escalationApprovers.description -join ', ')
                    $tableRows = "| Yes | $primaryApprovers | $escalationApprovers |`n"
                } else {
                    $testResultMarkdown = "❌ **Fail**: Approval required but no approvers configured.`n`n%TestResult%"
                    $tableRows = "| Yes | None | None |`n"
                }
            } else {
                $testResultMarkdown = "❌ **Fail**: Approval not required for Global Administrator role activation.`n`n%TestResult%"
                $tableRows = "| No | N/A | N/A |`n"
            }
        } else {
            $testResultMarkdown = "❌ **Fail**: No PIM policy found for Global Administrator role.`n`n%TestResult%"
            $tableRows = "| N/A | N/A | N/A |`n"
        }

        $passed = $result

        $reportTitle = 'Global Administrator role activation and approval workflow'

        $formatTemplate = @'

## {0}


| Approval Required | Primary Approvers | Escalation Approvers |
| :---------------- | :---------------- | :------------------- |
{1}

'@

        $mdInfo = $formatTemplate -f $reportTitle, $tableRows
        $testResultMarkdown = $testResultMarkdown -replace '%TestResult%', $mdInfo

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21817' -TestType 'Identity' -Status $(if ($passed) { 'Passed' } else { 'Failed' }) -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Global Administrator role activation triggers an approval workflow' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21817' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Global Administrator role activation triggers an approval workflow' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
