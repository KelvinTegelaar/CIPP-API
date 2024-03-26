function Invoke-CIPPStandardTAP {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }
    
    If ($Settings.remediate) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'TemporaryAccessPass' -Enabled $true -TAPisUsableOnce $Settings.config
        }
    }

    if ($Settings.alert) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is not enabled.' -sev Alert
        }
    }

    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'TemporaryAccessPass' -FieldValue [bool]$State -StoreAs bool -Tenant $tenant
    }
}
