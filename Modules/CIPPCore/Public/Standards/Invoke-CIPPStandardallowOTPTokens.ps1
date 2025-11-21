function Invoke-CIPPStandardallowOTPTokens {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) allowOTPTokens
    .SYNOPSIS
        (Label) Enable OTP via Authenticator
    .DESCRIPTION
        (Helptext) Allows you to use MS authenticator OTP token generator
        (DocsDescription) Allows you to use Microsoft Authenticator OTP token generator. Useful for using the NPS extension as MFA on VPN clients.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "EIDSCA.AM02"
        EXECUTIVETEXT
            Enables one-time password generation through Microsoft Authenticator app, providing an additional secure authentication method for employees. This is particularly useful for secure VPN access and other systems requiring multi-factor authentication.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2023-12-06
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'allowOTPTokens' -Settings $Settings

    try {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the allowOTPTokens state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        if ($CurrentInfo.isSoftwareOathEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is already enabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true -MicrosoftAuthenticatorSoftwareOathEnabled $true
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentInfo.isSoftwareOathEnabled) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'MS authenticator OTP/oAuth tokens is not enabled' -object $CurrentInfo -tenant $tenant -standardName 'allowOTPTokens' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'MS authenticator OTP/oAuth tokens is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.allowOTPTokens' -FieldValue $CurrentInfo.isSoftwareOathEnabled -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'MSAuthenticator' -FieldValue $CurrentInfo.isSoftwareOathEnabled -StoreAs bool -Tenant $tenant
    }

}
