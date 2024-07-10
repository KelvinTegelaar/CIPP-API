function Invoke-CIPPStandardallowOAuthTokens {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    allowOAuthTokens
    .CAT
    Entra (AAD) Standards
    .TAG
    "lowimpact"
    .HELPTEXT
    Allows you to use any software OAuth token generator
    .DOCSDESCRIPTION
    Enables OTP Software OAuth tokens for the tenant. This allows users to use OTP codes generated via software, like a password manager to be used as an authentication method.
    .ADDEDCOMPONENT
    .LABEL
    Enable OTP Software OAuth tokens
    .IMPACT
    Low Impact
    .POWERSHELLEQUIVALENT
    Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Allows you to use any software OAuth token generator
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'softwareOath' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'allowOAuthTokens: Invalid state parameter set' -sev Error
        Return
    }



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


}




