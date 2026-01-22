function Invoke-CippTestEIDSCAAG02 {
    <#
    .SYNOPSIS
    Authentication Methods - Report Suspicious Activity
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG02' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Authentication Methods - Report Suspicious Activity' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $SuspiciousActivityState = $AuthMethodsPolicy.reportSuspiciousActivitySettings.state

        if ($SuspiciousActivityState -eq 'enabled') {
            $Status = 'Passed'
            $Result = 'Report suspicious activity is enabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Report suspicious activity should be enabled to allow users to report fraudulent MFA attempts.

**Current Configuration:**
- reportSuspiciousActivitySettings.state: $SuspiciousActivityState

**Recommended Configuration:**
- reportSuspiciousActivitySettings.state: enabled

This feature helps detect and prevent unauthorized access attempts.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG02' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Authentication Methods - Report Suspicious Activity' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG02' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Authentication Methods - Report Suspicious Activity' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
