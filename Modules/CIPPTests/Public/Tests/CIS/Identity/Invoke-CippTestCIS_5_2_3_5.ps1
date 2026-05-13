function Invoke-CippTestCIS_5_2_3_5 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.5) - Weak authentication methods SHALL be disabled (SMS, Voice)
    #>
    param($Tenant)

    try {
        $AMP = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AMP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_5' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'High' -Name 'Weak authentication methods are disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $AMP | Select-Object -First 1
        $Sms = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Sms' } | Select-Object -First 1
        $Voice = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Voice' } | Select-Object -First 1

        $SmsDisabled = -not $Sms -or $Sms.state -eq 'disabled'
        $VoiceDisabled = -not $Voice -or $Voice.state -eq 'disabled'

        if ($SmsDisabled -and $VoiceDisabled) {
            $Status = 'Passed'
            $Result = 'SMS and Voice authentication methods are both disabled.'
        } else {
            $Status = 'Failed'
            $Result = "Weak methods are still enabled.`n`n- SMS state: $($Sms.state)`n- Voice state: $($Voice.state)"
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_5' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Weak authentication methods are disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_5' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Weak authentication methods are disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
