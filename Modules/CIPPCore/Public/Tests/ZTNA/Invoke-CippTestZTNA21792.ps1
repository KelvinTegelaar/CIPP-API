function Invoke-CippTestZTNA21792 {
    param($Tenant)
    #tested
    try {
        $AuthPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21792' -TestType 'Identity' -Status 'Investigate' -ResultMarkdown 'Authorization policy not found in database' -Risk 'Medium' -Name 'Guests have restricted access to directory objects' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
            return
        }

        $GuestRestrictedRoleId = '2af84b1e-32c8-42b7-82bc-daa82404023b'
        $GuestRoleId = $AuthPolicy.guestUserRoleId

        if ($GuestRoleId -eq $GuestRestrictedRoleId) {
            $Status = 'Passed'
            $Result = 'Guest user access is properly restricted'
        } else {
            $Status = 'Failed'
            $Result = 'Guest user access is not restricted'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21792' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Guests have restricted access to directory objects' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21792' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guests have restricted access to directory objects' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'External Collaboration'
    }
}
