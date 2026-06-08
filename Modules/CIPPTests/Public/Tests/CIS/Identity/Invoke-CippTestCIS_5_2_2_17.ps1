function Invoke-CippTestCIS_5_2_2_17 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.2.17) - Authentication transfer is blocked
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_17' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'Authentication transfer is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.conditions.applications.includeApplications -contains 'All' -and
            $_.conditions.authenticationFlows -and
            $_.conditions.authenticationFlows.transferMethods -match 'authenticationTransfer' -and
            $_.grantControls.builtInControls -contains 'block'
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies block authentication transfer:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy blocks the authenticationTransfer authentication flow for all users.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_17' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Authentication transfer is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_17' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Authentication transfer is blocked' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
