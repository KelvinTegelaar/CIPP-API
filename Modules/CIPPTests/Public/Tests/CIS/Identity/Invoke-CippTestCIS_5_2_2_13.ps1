function Invoke-CippTestCIS_5_2_2_13 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.2.13) - Periodic reauthentication is required for all users
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_13' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'Periodic reauthentication is required for all users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Session Management'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.conditions.applications.includeApplications -contains 'All' -and
            $_.sessionControls.signInFrequency -and
            $_.sessionControls.signInFrequency.isEnabled -eq $true -and
            $_.sessionControls.signInFrequency.frequencyInterval -eq 'timeBased' -and
            (
                ($_.sessionControls.signInFrequency.type -eq 'days' -and $_.sessionControls.signInFrequency.value -le 7) -or
                ($_.sessionControls.signInFrequency.type -eq 'hours' -and $_.sessionControls.signInFrequency.value -le 168)
            )
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies enforce periodic reauthentication (7 days or less) for all users:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName) ($($_.sessionControls.signInFrequency.value) $($_.sessionControls.signInFrequency.type))" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets all users with a periodic (timeBased) sign-in frequency of 7 days or less.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_13' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Periodic reauthentication is required for all users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Session Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_13' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Periodic reauthentication is required for all users' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Session Management'
    }
}
