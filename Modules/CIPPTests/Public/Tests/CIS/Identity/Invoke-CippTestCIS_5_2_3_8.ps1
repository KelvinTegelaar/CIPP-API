function Invoke-CippTestCIS_5_2_3_8 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.3.8) - Ensure that Account 'Lockout threshold' is '10' or less
    #>
    param($Tenant)

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_8' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Settings cache not found.' -Risk 'Medium' -Name "Account 'Lockout threshold' is '10' or less" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $PwdSetting = $Settings | Where-Object { $_.templateId -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' -or $_.displayName -eq 'Password Rule Settings' } | Select-Object -First 1

        if (-not $PwdSetting) {
            # Password Rule Settings object not present: tenant defaults apply (LockoutThreshold default = 10), which satisfies the recommendation.
            $Status = 'Passed'
            $Result = "Password Rule Settings not configured; the tenant default Lockout threshold of 10 applies, which is compliant (10 or less)."
        } else {
            $LockoutThreshold = ($PwdSetting.values | Where-Object { $_.name -eq 'LockoutThreshold' }).value

            if ([int]$LockoutThreshold -le 10) {
                $Status = 'Passed'
                $Result = "Account Lockout threshold is set to $([int]$LockoutThreshold), which is 10 or less."
            } else {
                $Status = 'Failed'
                $Result = "Account Lockout threshold is set to $([int]$LockoutThreshold), which exceeds the maximum recommended value of 10."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_8' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Account 'Lockout threshold' is '10' or less" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_8' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Account 'Lockout threshold' is '10' or less" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
