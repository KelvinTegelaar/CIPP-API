function Invoke-CippTestCIS_5_2_2_6 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.2.6) - Identity Protection user risk policies SHALL be enabled
    #>
    param($Tenant)

    try {
        $CA = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'

        if (-not $CA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_6' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ConditionalAccessPolicies cache not found.' -Risk 'High' -Name 'Identity Protection user risk policies are enabled' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Identity Protection'
            return
        }

        $Matching = $CA | Where-Object {
            $_.state -eq 'enabled' -and
            $_.conditions.userRiskLevels -and
            $_.conditions.userRiskLevels.Count -gt 0
        }

        if ($Matching) {
            $Status = 'Passed'
            $Result = "$($Matching.Count) Conditional Access policy/policies act on user risk:`n`n"
            $Result += ($Matching | ForEach-Object { "- $($_.displayName) (risk: $($_.conditions.userRiskLevels -join ', '))" }) -join "`n"
        } else {
            $Status = 'Failed'
            $Result = 'No enabled Conditional Access policy uses userRiskLevels. Create a policy that requires password change (or blocks) on High user risk.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_6' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Identity Protection user risk policies are enabled' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Identity Protection'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_2_6' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Identity Protection user risk policies are enabled' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Identity Protection'
    }
}
