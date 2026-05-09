function Invoke-CippTestCIS_5_1_2_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.1.2.1) - 'Per-user MFA' SHALL be disabled
    #>
    param($Tenant)

    try {
        $MFA = Get-CIPPTestData -TenantFilter $Tenant -Type 'MFAState'

        if (-not $MFA) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'MFAState cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name "'Per-user MFA' is disabled" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Enabled = $MFA | Where-Object { $_.PerUserMFAState -in @('Enabled', 'Enforced') }

        if (-not $Enabled -or $Enabled.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'No users have legacy per-user MFA enabled or enforced.'
        } else {
            $Status = 'Failed'
            $Result = "$($Enabled.Count) user(s) still have per-user MFA enabled or enforced — migrate them to Conditional Access:`n`n"
            $Result += ($Enabled | Select-Object -First 25 | ForEach-Object { "- $($_.userPrincipalName) ($($_.PerUserMFAState))" }) -join "`n"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "'Per-user MFA' is disabled" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_1_2_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "'Per-user MFA' is disabled" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
