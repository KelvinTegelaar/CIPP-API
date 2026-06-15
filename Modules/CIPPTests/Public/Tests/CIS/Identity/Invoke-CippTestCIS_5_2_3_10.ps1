function Invoke-CippTestCIS_5_2_3_10 {
    <#
    .SYNOPSIS
    Tests CIS M365 7.0.0 (5.2.3.10) - Ensure Microsoft Authenticator on companion applications is disabled
    #>
    param($Tenant)

    try {
        $AMP = Get-CIPPTestData -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AMP) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_10' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'AuthenticationMethodsPolicy cache not found.' -Risk 'Medium' -Name 'Microsoft Authenticator on companion applications is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $Cfg = $AMP | Select-Object -First 1
        $Authenticator = $Cfg.authenticationMethodConfigurations | Where-Object { $_.id -eq 'MicrosoftAuthenticator' } | Select-Object -First 1

        if (-not $Authenticator) {
            $Status = 'Failed'
            $Result = 'MicrosoftAuthenticator authentication method configuration not found.'
        } else {
            $CompanionState = $Authenticator.featureSettings.companionAppAllowedState.state

            if ($Authenticator.state -eq 'disabled') {
                $Status = 'Passed'
                $Result = 'Microsoft Authenticator is disabled, so companion applications (Authenticator Lite) cannot be used.'
            } elseif ($CompanionState -eq 'disabled') {
                $Status = 'Passed'
                $Result = 'Microsoft Authenticator on companion applications is disabled.'
            } else {
                $Status = 'Failed'
                $Result = "Microsoft Authenticator on companion applications is not disabled. Current companionAppAllowedState: $CompanionState"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_10' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Microsoft Authenticator on companion applications is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_10' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Microsoft Authenticator on companion applications is disabled' -UserImpact 'Medium' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
