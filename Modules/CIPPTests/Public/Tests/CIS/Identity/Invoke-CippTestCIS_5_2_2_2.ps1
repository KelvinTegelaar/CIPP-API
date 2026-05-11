function Invoke-CippTestCIS_5_2_2_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.2) - MFA SHALL be enabled for all users
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'MFA is enabled for all users' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.users.includeUsers -contains 'All' -and
            $_.grantControls -and
            ($_.grantControls.builtInControls -contains 'mfa' -or $_.grantControls.authenticationStrength) -and
            $_.conditions.applications.includeApplications -contains 'All'
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies require MFA for all users on all cloud apps:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName)" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy targets All users / All cloud apps with MFA.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'MFA is enabled for all users' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'MFA is enabled for all users' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Authentication'
    }
}
