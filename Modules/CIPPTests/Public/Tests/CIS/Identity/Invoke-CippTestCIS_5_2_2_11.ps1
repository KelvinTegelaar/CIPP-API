function Invoke-CippTestCIS_5_2_2_11 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.11) - Sign-in frequency for Intune Enrollment SHALL be 'Every time'
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_11' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'Medium' -Name "Sign-in frequency for Intune Enrollment is 'Every time'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device Management'
            return
        }

        # Microsoft Intune Enrollment app GUID
        $IntuneEnrollmentApp = 'd4ebce55-015a-49b5-a083-c84d1797ae8c'

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.applications.includeApplications -contains $IntuneEnrollmentApp -and
            $_.sessionControls -and
            $_.sessionControls.signInFrequency -and
            $_.sessionControls.signInFrequency.frequencyInterval -eq 'everyTime'
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies require sign-in every time for Intune Enrollment:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets Microsoft Intune Enrollment with sign-in frequency Every time.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_11' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Sign-in frequency for Intune Enrollment is 'Every time'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_11' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Sign-in frequency for Intune Enrollment is 'Every time'" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Device Management'
    }
}
