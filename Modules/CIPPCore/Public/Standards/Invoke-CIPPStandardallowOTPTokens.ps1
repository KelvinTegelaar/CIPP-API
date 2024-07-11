function Invoke-CIPPStandardallowOTPTokens {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    allowOTPTokens
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Allows you to use MS authenticator OTP token generator
    .DOCSDESCRIPTION
    Allows you to use Microsoft Authenticator OTP token generator. Useful for using the NPS extension as MFA on VPN clients.
    .ADDEDCOMPONENT
    .LABEL
    Enable OTP via Authenticator
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Allows you to use MS authenticator OTP token generator
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
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




