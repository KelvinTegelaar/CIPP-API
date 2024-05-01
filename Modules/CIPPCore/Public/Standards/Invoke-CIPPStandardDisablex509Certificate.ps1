function Invoke-CIPPStandardDisablex509Certificate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/x509Certificate' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'x509Certificate' -Enabled $false
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'x509Certificate authentication method is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'Disablex509Certificate' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

}
