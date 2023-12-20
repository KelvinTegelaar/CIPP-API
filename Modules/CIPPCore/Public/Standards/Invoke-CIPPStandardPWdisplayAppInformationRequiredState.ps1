function Invoke-CIPPStandardPWdisplayAppInformationRequiredState {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    
    If ($Settings.remediate) {
        Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true
    }
    # This is ugly but done to avoid a second call to the Graph API
    if ($Settings.alert -or $Settings.report) {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
        $State = if ($CurrentInfo.featureSettings.displayAppInformationRequiredState.state -eq 'enabled') { $true } else { $false }
        
        if ($Settings.alert) {
            if ($State) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is enabled.' -sev Info
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is not enabled.' -sev Alert
            }
        }
        if ($Settings.report) {
            Add-CIPPBPAField -FieldName 'PWdisplayAppInformationRequiredState' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
        }
    }
}