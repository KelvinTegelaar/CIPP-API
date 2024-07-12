function Invoke-CIPPStandardallowOAuthTokens {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) allowOAuthTokens
    .SYNOPSIS
        (Label) Enable OTP Software OAuth tokens
    .DESCRIPTION
        (Helptext) Allows you to use any software OAuth token generator
        (DocsDescription) Enables OTP Software OAuth tokens for the tenant. This allows users to use OTP codes generated via software, like a password manager to be used as an authentication method.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "lowimpact"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'softwareOath' -Enabled $true
        }
    }

    if ($Settings.alert -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'softwareOath' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

}
