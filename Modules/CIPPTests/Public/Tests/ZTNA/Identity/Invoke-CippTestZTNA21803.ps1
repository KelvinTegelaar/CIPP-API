function Invoke-CippTestZTNA21803 {
    <#
    .SYNOPSIS
    Migrate from legacy MFA and SSPR policies
    #>
    param($Tenant)
    #Tested
    try {
        $AuthMethodsPolicy = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21803' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Migrate from legacy MFA and SSPR policies' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential management'
            return
        }

        $PolicyMigrationState = $AuthMethodsPolicy.policyMigrationState

        if ([string]::IsNullOrEmpty($PolicyMigrationState)) {
            $Status = 'Passed'
            $Result = 'No legacy policies to migrate. This tenant is using modern authentication methods.'
        } elseif ($PolicyMigrationState -eq 'migrationComplete') {
            $Status = 'Passed'
            $Result = 'Migration from legacy MFA and SSPR policies is complete. Authentication methods are managed by the authentication methods policy.'
        } elseif ($PolicyMigrationState -eq 'migrationInProgress') {
            $Status = 'Investigate'
            $Result = 'Tenant migration from legacy MFA and SSPR policies is in progress'
        } else {
            $Status = 'Failed'
            $Result = "Tenant has not migrated from legacy MFA and SSPR policies (state: $PolicyMigrationState)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21803' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Migrate from legacy MFA and SSPR policies' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21803' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Migrate from legacy MFA and SSPR policies' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Credential management'
    }
}
