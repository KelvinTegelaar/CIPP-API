function Invoke-CippTestEIDSCAAG01 {
    <#
    .SYNOPSIS
    Authentication Methods - Policy Migration
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Authentication Methods - Policy Migration' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $MigrationState = $AuthMethodsPolicy.policyMigrationState

        if ($MigrationState -in @('migrationComplete', '')) {
            $Status = 'Passed'
            $Result = "Policy migration is complete or not applicable: $MigrationState"
        } else {
            $Status = 'Failed'
            $Result = @"
The authentication methods policy migration should be complete.

**Current Configuration:**
- policyMigrationState: $MigrationState

**Recommended Configuration:**
- policyMigrationState: migrationComplete or empty

Complete the migration to use the modern authentication methods policy.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Authentication Methods - Policy Migration' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Authentication Methods - Policy Migration' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
