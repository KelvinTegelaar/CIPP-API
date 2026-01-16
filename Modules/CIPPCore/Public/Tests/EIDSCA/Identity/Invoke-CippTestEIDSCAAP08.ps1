function Invoke-CippTestEIDSCAAP08 {
    <#
    .SYNOPSIS
    Authorization Policy - User Consent Policy
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP08' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authorization Policy - User Consent Policy' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $ConsentPolicy = $AuthorizationPolicy.permissionGrantPolicyIdsAssignedToDefaultUserRole
        $ExpectedPolicy = 'ManagePermissionGrantsForSelf.microsoft-user-default-low'

        if ($ConsentPolicy -contains $ExpectedPolicy) {
            $Status = 'Passed'
            $Result = 'User consent policy is set to low-risk permissions'
        } else {
            $Status = 'Failed'
            $Result = @"
User consent policy should be configured to only allow consent for low-risk applications.

**Current Configuration:**
- permissionGrantPolicyIdsAssignedToDefaultUserRole: $($ConsentPolicy -join ', ')

**Recommended Configuration:**
- permissionGrantPolicyIdsAssignedToDefaultUserRole: $ExpectedPolicy

This limits users to only consent to applications with low-risk permissions.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP08' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authorization Policy - User Consent Policy' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP08' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authorization Policy - User Consent Policy' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
