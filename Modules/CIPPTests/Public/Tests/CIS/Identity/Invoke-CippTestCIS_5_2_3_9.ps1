function Invoke-CippTestCIS_5_2_3_9 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.3.9) - Ensure that Account 'Lockout duration in seconds' is at least 60 seconds
    #>
    param($Tenant)

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_9' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Settings cache not found.' -Risk 'Medium' -Name "Account 'Lockout duration in seconds' is at least 60 seconds" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $PwdSetting = $Settings | Where-Object { $_.templateId -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' -or $_.displayName -eq 'Password Rule Settings' } | Select-Object -First 1

        if (-not $PwdSetting) {
            # Password Rule Settings object not present: tenant defaults apply (LockoutDurationInSeconds default = 60), which satisfies the recommendation.
            $Status = 'Passed'
            $Result = "Password Rule Settings not configured; the tenant default Lockout duration of 60 seconds applies, which is compliant (at least 60 seconds)."
        } else {
            $LockoutDuration = ($PwdSetting.values | Where-Object { $_.name -eq 'LockoutDurationInSeconds' }).value

            if ([int]$LockoutDuration -ge 60) {
                $Status = 'Passed'
                $Result = "Account Lockout duration is set to $([int]$LockoutDuration) seconds, which is at least 60 seconds."
            } else {
                $Status = 'Failed'
                $Result = "Account Lockout duration is set to $([int]$LockoutDuration) seconds, which is less than the minimum recommended value of 60 seconds."
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_9' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name "Account 'Lockout duration in seconds' is at least 60 seconds" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_9' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name "Account 'Lockout duration in seconds' is at least 60 seconds" -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
