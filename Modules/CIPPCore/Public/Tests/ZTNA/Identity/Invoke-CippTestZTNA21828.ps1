function Invoke-CippTestZTNA21828 {
    <#
    .SYNOPSIS
    Authentication transfer is blocked
    #>
    param($Tenant)
    #Tested
    try {
        $allCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $allCAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21828' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authentication transfer is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Conditional Access'
            return
        }

        $matchedPolicies = $allCAPolicies | Where-Object {
            $_.conditions.authenticationFlows.transferMethods -match 'authenticationTransfer' -and
            $_.grantControls.builtInControls -contains 'block' -and
            $_.conditions.users.includeUsers -eq 'all' -and
            $_.conditions.applications.includeApplications -eq 'all' -and
            $_.state -eq 'enabled'
        }

        if ($matchedPolicies.Count -gt 0) {
            $passed = 'Passed'
            $testResultMarkdown = 'Authentication transfer is blocked by Conditional Access Policy(s).'
        } else {
            $passed = 'Failed'
            $testResultMarkdown = 'Authentication transfer is not blocked.'
        }

        $reportTitle = 'Conditional Access Policies targeting Authentication Transfer'

        if ($matchedPolicies.Count -gt 0) {
            $mdInfo = "`n## $reportTitle`n`n"
            $mdInfo += "| Policy Name | Policy ID | State | Created | Modified |`n"
            $mdInfo += "| :---------- | :-------- | :---- | :------ | :------- |`n"

            foreach ($policy in $matchedPolicies) {
                $created = if ($policy.createdDateTime) { $policy.createdDateTime } else { 'N/A' }
                $modified = if ($policy.modifiedDateTime) { $policy.modifiedDateTime } else { 'N/A' }
                $mdInfo += "| $($policy.displayName) | $($policy.id) | $($policy.state) | $created | $modified |`n"
            }

            $testResultMarkdown = $testResultMarkdown + $mdInfo
        } else {
            $testResultMarkdown = $testResultMarkdown + "`n`nNo Conditional Access policies targeting authentication transfer."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21828' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Authentication transfer is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Conditional Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21828' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authentication transfer is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Conditional Access'
    }
}
