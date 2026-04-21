function Invoke-CippTestZTNA21810 {
    <#
    .SYNOPSIS
    Resource-specific consent is restricted
    #>
    param($Tenant)
    #Tested
    try {
        $authPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $authPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21810' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Resource-specific consent is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $teamPermission = 'managepermissiongrantsforownedresource.microsoft-dynamically-managed-permissions-for-team'
        $hasTeamPermission = $authPolicy.permissionGrantPolicyIdsAssignedToDefaultUserRole -contains $teamPermission

        if (-not $hasTeamPermission) {
            $state = 'DisabledForAllApps'
        } else {
            $state = 'EnabledForAllApps'
        }

        if ($state -eq 'DisabledForAllApps') {
            $passed = 'Passed'
            $testResultMarkdown = "Resource-Specific Consent is restricted.`n`nThe current state is $state."
        } else {
            $passed = 'Failed'
            $testResultMarkdown = "Resource-Specific Consent is not restricted.`n`nThe current state is $state."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21810' -TestType 'Identity' -Status $passed -ResultMarkdown $testResultMarkdown -Risk 'Medium' -Name 'Resource-specific consent is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21810' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Resource-specific consent is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
