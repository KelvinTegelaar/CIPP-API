function Invoke-CippTestCIS_1_3_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (1.3.2) - Idle session timeout SHALL be 3 hours or less for unmanaged devices
    #>
    param($Tenant)

    try {
        $CAPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CAPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'Idle session timeout' is set to '3 hours or less' for unmanaged devices" -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Session Management'
            return
        }

        # CIS recommends a CA policy for unmanaged devices that enforces session signInFrequency <= 3 hours
        $Matching = $CAPolicies | Where-Object {
            $_.state -eq 'enabled' -and
            $_.sessionControls -and
            $_.sessionControls.signInFrequency -and
            $_.sessionControls.signInFrequency.isEnabled -eq $true -and
            (
                ($_.sessionControls.signInFrequency.type -eq 'hours' -and [int]$_.sessionControls.signInFrequency.value -le 3) -or
                ($_.sessionControls.signInFrequency.type -eq 'days' -and [int]$_.sessionControls.signInFrequency.value -eq 0)
            )
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies enforce sign-in frequency of 3 hours or less:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy enforces a sign-in frequency of 3 hours or less. Create a CA policy targeting unmanaged devices with signInFrequency configured.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'Idle session timeout' is set to '3 hours or less' for unmanaged devices" -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Session Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_1_3_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'Idle session timeout' is set to '3 hours or less' for unmanaged devices" -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Session Management'
    }
}
