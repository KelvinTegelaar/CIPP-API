function Invoke-CippTestEIDSCAAP06 {
    <#
    .SYNOPSIS
    Authorization Policy - Email Validation Join
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP06' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authorization Policy - Email Validation Join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowEmailVerified = $AuthorizationPolicy.allowEmailVerifiedUsersToJoinOrganization

        if ($AllowEmailVerified -eq $false) {
            $Status = 'Passed'
            $Result = 'Users cannot join the tenant by email validation'
        } else {
            $Status = 'Failed'
            $Result = @"
Email-validated users should not be allowed to join the organization to prevent unauthorized access.

**Current Configuration:**
- allowEmailVerifiedUsersToJoinOrganization: $AllowEmailVerified

**Recommended Configuration:**
- allowEmailVerifiedUsersToJoinOrganization: false

Disabling this feature prevents unauthorized users from self-registering into your tenant.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP06' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authorization Policy - Email Validation Join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP06' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authorization Policy - Email Validation Join' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
