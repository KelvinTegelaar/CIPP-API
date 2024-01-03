function Invoke-CIPPStandardDisableEmail {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    If ($Settings.remediate) {
        Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Email' -Enabled $false
    }

    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Email' -tenantid $Tenant
        $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

        if ($Settings.alert) {
            if ($State) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email Support is enabled' -sev Alert
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email Support is not enabled' -sev Info
            }
        }
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'DisableEmail' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
        }
    }
}
