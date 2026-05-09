function Invoke-CippTestCIS_5_1_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.3.1) - A dynamic group for guest users SHALL be created
    #>
    param($Tenant)

    try {
        $Groups = Get-CIPPTestData -TenantFilter $Tenant -Type 'Groups'

        if (-not $Groups) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Groups cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'A dynamic group for guest users is created' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
            return
        }

        $GuestDynamic = $Groups | Where-Object {
            $_.groupTypes -contains 'DynamicMembership' -and
            $_.membershipRule -match "userType\s*-eq\s*['""]Guest['""]"
        }

        if ($GuestDynamic.Count -gt 0) {
            $Status = 'Passed'
            $Result = "$($GuestDynamic.Count) dynamic group(s) target guest users:`n`n"
            $Result += ($GuestDynamic | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No dynamic security group targeting `userType -eq "Guest"` was found. Create one so guest-targeted Conditional Access can use it.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'A dynamic group for guest users is created' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'A dynamic group for guest users is created' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Group Management'
    }
}
