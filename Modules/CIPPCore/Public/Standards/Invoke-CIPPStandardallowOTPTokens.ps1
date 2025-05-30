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

    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant

    If ($Settings.remediate -eq $true) {
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
