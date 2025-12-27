function Invoke-CippTestZTNA21803 {
    param($Tenant)
    #Tested
    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21803' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Authentication methods policy not found in database' -Risk 'Medium' -Name 'Migrate from legacy MFA and SSPR policies' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential Management'
            return
        }

        $PolicyMigrationState = $AuthMethodsPolicy.policyMigrationState

        if ($PolicyMigrationState -eq 'migrationComplete') {
            $Status = 'Passed'
            $Result = 'Tenant has migrated from legacy MFA and SSPR policies to authentication methods policy'
        } elseif ($PolicyMigrationState -eq 'migrationInProgress') {
            $Status = 'Investigate'
            $Result = 'Tenant migration from legacy MFA and SSPR policies is in progress'
        } else {
            $Status = 'Failed'
            $Result = "Tenant has not migrated from legacy MFA and SSPR policies (state: $PolicyMigrationState)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21803' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Migrate from legacy MFA and SSPR policies' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21803' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Migrate from legacy MFA and SSPR policies' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Credential Management'
    }
}
