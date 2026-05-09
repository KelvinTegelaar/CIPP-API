function Invoke-CippTestCIS_5_2_2_8 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.8) - 'sign-in risk' SHALL be blocked for medium and high risk
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_8' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name "'sign-in risk' is blocked for medium and high risk" -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Identity Protection'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.signInRiskLevels -contains 'medium' -and
            $_.conditions.signInRiskLevels -contains 'high' -and
            $_.grantControls.builtInControls -contains 'block'
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies block medium+high sign-in risk:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy blocks both medium and high sign-in risk.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_8' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name "'sign-in risk' is blocked for medium and high risk" -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Identity Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_8' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name "'sign-in risk' is blocked for medium and high risk" -UserImpact 'High' -ImplementationEffort 'Medium' -Category 'Identity Protection'
    }
}
