function Invoke-CIPPStandardallowOTPTokens {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
        if ($CurrentInfo.isSoftwareOathEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true -MicrosoftAuthenticatorSoftwareOathEnabled $true
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.isSoftwareOathEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'MSAuthenticator' -FieldValue $CurrentInfo.isSoftwareOathEnabled -StoreAs bool -Tenant $tenant
    }

}