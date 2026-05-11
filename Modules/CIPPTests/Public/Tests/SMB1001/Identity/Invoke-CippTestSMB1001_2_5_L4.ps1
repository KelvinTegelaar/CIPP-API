function Invoke-CippTestSMB1001_2_5_L4 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.5/2.6/2.9 Level 4+) - Weak MFA factors disabled (SMS, Voice, Email)

    .DESCRIPTION
    SMB1001 Level 4 hardens MFA controls 2.5, 2.6, 2.9 by prohibiting SMS, Voice, Text and
    Email as second factors. Only Authenticator App, phone-based push, or U2F/FIDO2 may be
    used. This test verifies the Authentication Methods Policy disables SMS, Voice, and Email.
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_5_L4'
    $Name = 'Phishing-resistant MFA factors are enforced (SMS, Voice, Email disabled)'

    try {
        $AMP = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AMP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $AMP | Select-Object -First 1
        $Sms   = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Sms' }   | Select-Object -First 1
        $Voice = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Voice' } | Select-Object -First 1
        $Email = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Email' } | Select-Object -First 1

        $WeakStill = @(
            if ($Sms   -and $Sms.state   -ne 'disabled') { "SMS ($($Sms.state))" }
            if ($Voice -and $Voice.state -ne 'disabled') { "Voice ($($Voice.state))" }
            if ($Email -and $Email.state -ne 'disabled') { "Email ($($Email.state))" }
        )

        if ($WeakStill.Count -eq 0) {
            $Status = 'Passed'
            $Result = 'SMS, Voice and Email authentication methods are all disabled. Phishing-resistant factors (Authenticator app, FIDO2, Hardware OATH) are the only paths.'
        } else {
            $Status = 'Failed'
            $Result = "Level 4/5 of SMB1001 prohibits SMS/Voice/Email as MFA factors. The following weak methods remain enabled:`n`n- $($WeakStill -join "`n- ")`n`nDisable each via the Authentication Methods Policy."
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
