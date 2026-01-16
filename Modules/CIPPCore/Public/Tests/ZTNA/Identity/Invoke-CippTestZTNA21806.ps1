function Invoke-CippTestZTNA21806 {
    <#
    .SYNOPSIS
    Secure the MFA registration (My Security Info) page
    #>
    param($Tenant)
    #tested
    try {
        $allCAPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $allCAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21806' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Secure the MFA registration (My Security Info) page' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Conditional Access'
            return
        }

        $matchedPolicies = $allCAPolicies | Where-Object {
            ($_.conditions.applications.includeUserActions -contains 'urn:user:registersecurityinfo') -and
            ($_.conditions.users.includeUsers -contains 'All') -and
            $_.state -eq 'enabled'
        }

        $testResultMarkdown = ''

        if ($matchedPolicies.Count -gt 0) {
            $passed = 'Passed'
            $testResultMarkdown = 'Security information registration is protected by Conditional Access policies.'
        } else {
            $passed = 'Failed'
            $testResultMarkdown = 'Security information registration is not protected by Conditional Access policies.'
        }

        $reportTitle = 'Conditional Access Policies targeting security information registration'
        $tableRows = ''

        if ($matchedPolicies.Count -gt 0) {
            $mdInfo = "`n## $reportTitle`n`n"
            $mdInfo += "| Policy Name | User Actions Targeted | Grant Controls Applied |`n"
            $mdInfo += "| :---------- | :-------------------- | :--------------------- |`n"

            foreach ($policy in $matchedPolicies) {
                $mdInfo += "| $($policy.displayName) | $($policy.conditions.applications.includeUserActions) | $($policy.grantControls.builtInControls -join ', ') |`n"
            }
        } else {
            $mdInfo = 'No Conditional Access policies targeting security information registration.'
        }

        $testResultMarkdown = $testResultMarkdown + $mdInfo

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21806' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'High' -Name 'Secure the MFA registration (My Security Info) page' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21806' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Secure the MFA registration (My Security Info) page' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Conditional Access'
    }
}
