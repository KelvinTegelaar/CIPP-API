function Invoke-CIPPStandardTAP {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/TemporaryAccessPass' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'TemporaryAccessPass' -FieldValue $State -StoreAs bool -Tenant $tenant
    }

    # Input validation
    if (([string]::IsNullOrWhiteSpace($Settings.state) -or $Settings.state -eq 'Select a value') -and ($Settings.remediate -eq $true -or $Settings.alert -eq $true)) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message 'TAP: Invalid state parameter set' -sev Error
        Return
    }

    If ($Settings.remediate -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'TemporaryAccessPass' -Enabled $true -TAPisUsableOnce $Settings.config
        }
    }

    if ($Settings.alert -eq $true) {
        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Temporary Access Passwords is not enabled.' -sev Alert
        }
    }
}
