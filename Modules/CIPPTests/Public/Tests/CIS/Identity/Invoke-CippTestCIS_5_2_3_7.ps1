function Invoke-CippTestCIS_5_2_3_7 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.7) - The email OTP authentication method SHALL be disabled
    #>
    param($Tenant)

    try {
        $AMP = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AMP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_7' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'Medium' -Name 'The email OTP authentication method is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $AMP | Select-Object -First 1
        $Email = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Email' } | Select-Object -First 1

        if (-not $Email -or $Email.state -eq 'disabled') {
            $Status = 'Passed'
            $Result = 'Email OTP authentication method is disabled.'
        } else {
            $Status = 'Failed'
            $Result = "Email OTP authentication method is enabled (state: $($Email.state))."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_7' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'The email OTP authentication method is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_7' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'The email OTP authentication method is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
