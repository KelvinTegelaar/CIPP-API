function Invoke-CippTestEIDSCAAP04 {
    <#
    .SYNOPSIS
    Authorization Policy - Guest Invite Restrictions
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP04' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authorization Policy - Guest Invite Restrictions' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowInvitesFrom = $AuthorizationPolicy.allowInvitesFrom

        if ($AllowInvitesFrom -in @('adminsAndGuestInviters', 'none')) {
            $Status = 'Passed'
            $Result = "Guest invite restrictions are properly configured: $AllowInvitesFrom"
        } else {
            $Status = 'Failed'
            $Result = @"
Guest invite restrictions should be set to limit who can invite guests for enhanced security.

**Current Configuration:**
- allowInvitesFrom: $AllowInvitesFrom

**Recommended Configuration:**
- allowInvitesFrom: adminsAndGuestInviters OR none

Restricting guest invitations helps maintain control over external access to your tenant.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP04' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authorization Policy - Guest Invite Restrictions' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP04' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authorization Policy - Guest Invite Restrictions' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
