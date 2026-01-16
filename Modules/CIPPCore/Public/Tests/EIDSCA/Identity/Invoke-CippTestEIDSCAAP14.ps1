function Invoke-CippTestEIDSCAAP14 {
    <#
    .SYNOPSIS
    Authorization Policy - Users Can Read Other Users
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP14' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Low' -Name 'Authorization Policy - Users Can Read Other Users' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowedToReadOtherUsers = $AuthorizationPolicy.defaultUserRolePermissions.allowedToReadOtherUsers

        if ($AllowedToReadOtherUsers -eq $true) {
            $Status = 'Passed'
            $Result = 'Users can read other users (standard behavior for collaboration)'
        } else {
            $Status = 'Failed'
            $Result = @"
Users should be allowed to read other users' basic profile information for collaboration purposes.

**Current Configuration:**
- defaultUserRolePermissions.allowedToReadOtherUsers: $AllowedToReadOtherUsers

**Recommended Configuration:**
- defaultUserRolePermissions.allowedToReadOtherUsers: true

This setting enables basic collaboration features like Teams and SharePoint.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP14' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Low' -Name 'Authorization Policy - Users Can Read Other Users' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP14' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Low' -Name 'Authorization Policy - Users Can Read Other Users' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
