function Invoke-CippTestEIDSCAAP01 {
    <#
    .SYNOPSIS
    Authorization Policy - Self-Service Password Reset for Admins
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP01' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authorization Policy - Self-Service Password Reset for Admins' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowedToUseSSPR = $AuthorizationPolicy.allowedToUseSSPR

        if ($AllowedToUseSSPR -eq $false) {
            $Status = 'Passed'
            $Result = 'Self-service password reset for administrators is disabled'
        } else {
            $Status = 'Failed'
            $Result = @"
Self-service password reset for administrators should be disabled for enhanced security.

**Current Configuration:**
- allowedToUseSSPR: $AllowedToUseSSPR

**Recommended Configuration:**
- allowedToUseSSPR: false

Administrators should follow more stringent password reset procedures rather than self-service options.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP01' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authorization Policy - Self-Service Password Reset for Admins' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP01' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authorization Policy - Self-Service Password Reset for Admins' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
