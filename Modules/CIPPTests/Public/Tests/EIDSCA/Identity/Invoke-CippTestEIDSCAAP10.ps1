function Invoke-CippTestEIDSCAAP10 {
    <#
    .SYNOPSIS
    Authorization Policy - Users Can Create Apps
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP10' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Authorization Policy - Users Can Create Apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $AllowedToCreateApps = $AuthorizationPolicy.defaultUserRolePermissions.allowedToCreateApps

        if ($AllowedToCreateApps -eq $false) {
            $Status = 'Passed'
            $Result = 'Users cannot create application registrations'
        } else {
            $Status = 'Failed'
            $Result = @"
Users should not be allowed to create application registrations by default to maintain control over applications.

**Current Configuration:**
- defaultUserRolePermissions.allowedToCreateApps: $AllowedToCreateApps

**Recommended Configuration:**
- defaultUserRolePermissions.allowedToCreateApps: false

Only authorized users should be able to register applications in your tenant.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP10' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Authorization Policy - Users Can Create Apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP10' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Authorization Policy - Users Can Create Apps' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
