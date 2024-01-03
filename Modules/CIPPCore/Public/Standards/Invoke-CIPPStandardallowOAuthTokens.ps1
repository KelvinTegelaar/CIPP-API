function Invoke-CIPPStandardallowOAuthTokens {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    If ($Settings.remediate) {    
        Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'softwareOath' -Enabled $true
    }

    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/softwareOath' -tenantid $Tenant
        $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

        if ($Settings.alert) {
            if ($State) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is enabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Software OTP/oAuth tokens is not enabled' -sev Alert
            }
        }
        
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'softwareOath' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
        }
    }
}