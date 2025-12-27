function Invoke-CippTestZTNA21810 {
    param($Tenant)
    #Tested
    try {
        $authPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $authPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21810' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Authorization policy not found in database' -Risk 'Medium' -Name 'Resource-specific consent is restricted' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application Management'
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
