function Invoke-CippTestCIS_5_2_3_1 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.1) - Microsoft Authenticator SHALL be configured to protect against MFA fatigue
    #>
    param($Tenant)

    try {
        $AMP = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AMP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_1' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'High' -Name 'Microsoft Authenticator is configured to protect against MFA fatigue' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $AMP | Select-Object -First 1
        $Authenticator = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' } | Select-Object -First 1

        if (-not $Authenticator) {
            $Status = 'Failed'
            $Result = 'MicrosoftAuthenticator authentication method configuration not found.'
        } else {
            $Inc = $Authenticator.featureSettings.displayAppInformationRequiredState.includeTarget.id
            $Geo = $Authenticator.featureSettings.displayLocationInformationRequiredState.includeTarget.id

            if ($Authenticator.state -eq 'enabled' -and
                $Authenticator.featureSettings.displayAppInformationRequiredState.state -eq 'enabled' -and
                $Authenticator.featureSettings.displayLocationInformationRequiredState.state -eq 'enabled' -and
                $Inc -eq 'all_users' -and $Geo -eq 'all_users') {
                $Status = 'Passed'
                $Result = 'Microsoft Authenticator has app context + geographic location enabled for all users.'
            } else {
                $Status = 'Failed'
                $Result = "Microsoft Authenticator is not fully hardened.`n`n- state: $($Authenticator.state)`n- displayAppInformation: $($Authenticator.featureSettings.displayAppInformationRequiredState.state) (target: $Inc)`n- displayLocation: $($Authenticator.featureSettings.displayLocationInformationRequiredState.state) (target: $Geo)"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_1' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Microsoft Authenticator is configured to protect against MFA fatigue' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_1' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Microsoft Authenticator is configured to protect against MFA fatigue' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
