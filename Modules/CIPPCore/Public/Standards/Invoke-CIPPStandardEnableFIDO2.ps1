function Invoke-CIPPStandardEnableFIDO2 {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    If ($Settings.remediate) {
        Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'Fido2' -Enabled $true
    }

    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/Fido2' -tenantid $Tenant
        
        if ($Settings.alert) {
            if ($CurrentInfo.state -eq 'enabled') {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is enabled' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'FIDO2 Support is not enabled' -sev Alert
            }
        }
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'EnableFIDO2' -FieldValue [bool]$CurrentInfo.state -StoreAs bool -Tenant $tenant
        }
    }
}
