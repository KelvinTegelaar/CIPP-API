function Invoke-CIPPStandardPWdisplayAppInformationRequiredState {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/microsoftAuthenticator' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }
    
    If ($Settings.remediate) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Passwordless with Information and Number Matching is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'MicrosoftAuthenticator' -Enabled $true
        }
    }

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