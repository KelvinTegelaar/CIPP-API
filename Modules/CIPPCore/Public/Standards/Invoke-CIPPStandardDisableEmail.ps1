function Invoke-CIPPStandardDisableEmail {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Email' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }
    
    If ($Settings.remediate) {
        if ($State) {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Email' -Enabled $false
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email authentication method is already disabled.' -sev Info
        }
    }

    if ($Settings.alert) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email authentication method is enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Email authentication method is not enabled' -sev Info
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableEmail' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}
