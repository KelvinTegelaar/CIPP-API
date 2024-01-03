function Invoke-CIPPStandardallowOTPTokens {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    If ($Settings.remediate) {
        Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true -MicrosoftAuthenticatorSoftwareOathEnabled $true
    }

    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = new-graphgetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
        if ($Settings.alert) {
        
            if ($CurrentInfo.isSoftwareOathEnabled) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is enabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is not enabled' -sev Alert
            }
        }

        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'MSAuthenticator' -FieldValue [bool]$CurrentInfo.isSoftwareOathEnabled -StoreAs bool -Tenant $tenant
        }
    }
}