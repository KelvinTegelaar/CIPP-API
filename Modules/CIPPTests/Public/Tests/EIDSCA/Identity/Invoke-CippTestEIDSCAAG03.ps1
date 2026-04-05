function Invoke-CippTestEIDSCAAG03 {
    <#
    .SYNOPSIS
    Authentication Methods - Suspicious Activity Target
    #>
    param($Tenant)

    try {
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG03' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Authentication Methods - Suspicious Activity Target' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
            return
        }

        $IncludeTargetId = $AuthMethodsPolicy.reportSuspiciousActivitySettings.includeTarget.id

        if ($IncludeTargetId -eq 'all_users') {
            $Status = 'Passed'
            $Result = 'Report suspicious activity is enabled for all users'
        } else {
            $Status = 'Failed'
            $Result = @"
Report suspicious activity should be enabled for all users.

**Current Configuration:**
- reportSuspiciousActivitySettings.includeTarget.id: $IncludeTargetId

**Recommended Configuration:**
- reportSuspiciousActivitySettings.includeTarget.id: all_users

All users should be able to report suspicious authentication attempts.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG03' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Authentication Methods - Suspicious Activity Target' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAG03' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Authentication Methods - Suspicious Activity Target' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication Methods'
    }
}
