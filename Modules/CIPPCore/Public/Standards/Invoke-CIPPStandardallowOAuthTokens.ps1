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
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2022-12-18
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#low-impact
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'AddDKIM' -Settings $Settings

    $CurrentState = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -tenantid $Tenant
    $StateIsCorrect = ($CurrentState.state -eq 'enabled')

    If ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is already enabled.' -sev Info
        } else {
            try {
                Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'softwareOath' -Enabled $true
            } catch {
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is enabled' -sev Info
        } else {
            Write-StandardsAlert -message 'Software OTP/oAuth tokens is not enabled' -object $CurrentState -tenant $tenant -standardName 'allowOAuthTokens' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'softwareOath' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        Set-CIPPStandardsCompareField -FieldName 'standards.allowOAuthTokens' -FieldValue $StateIsCorrect -TenantFilter $tenant
    }
}
