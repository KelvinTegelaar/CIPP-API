function Invoke-CIPPStandardallowOAuthTokens {
    <#
    .FUNCTIONALITY
    Internal
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
