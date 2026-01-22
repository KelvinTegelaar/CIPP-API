function Invoke-CippTestEIDSCAAP07 {
    <#
    .SYNOPSIS
    Authorization Policy - Guest User Access
    #>
    param($Tenant)

    try {
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP07' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Authorization Policy - Guest User Access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
            return
        }

        $GuestUserRoleId = $AuthorizationPolicy.guestUserRoleId
        $ExpectedRoleId = '2af84b1e-32c8-42b7-82bc-daa82404023b'

        if ($GuestUserRoleId -eq $ExpectedRoleId) {
            $Status = 'Passed'
            $Result = 'Guest user access is restricted (most restrictive)'
        } else {
            $Status = 'Failed'
            $Result = @"
Guest user access should be set to the most restrictive level for enhanced security.

**Current Configuration:**
- guestUserRoleId: $GuestUserRoleId

**Recommended Configuration:**
- guestUserRoleId: $ExpectedRoleId (Most restrictive guest permissions)

This setting limits what guest users can see and do in your directory.
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP07' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authorization Policy - Guest User Access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'EIDSCAAP07' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authorization Policy - Guest User Access' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authorization Policy'
    }
}
