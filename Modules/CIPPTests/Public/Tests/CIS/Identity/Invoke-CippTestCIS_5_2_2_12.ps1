function Invoke-CippTestCIS_5_2_2_12 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.12) - The device code sign-in flow SHALL be blocked
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_12' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'The device code sign-in flow is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.authenticationFlows -and
            $_.conditions.authenticationFlows.transferMethods -match 'deviceCodeFlow' -and
            $_.grantControls.builtInControls -contains 'block'
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies block the device code flow:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy blocks the deviceCodeFlow authentication flow.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_12' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'The device code sign-in flow is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_12' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'The device code sign-in flow is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
