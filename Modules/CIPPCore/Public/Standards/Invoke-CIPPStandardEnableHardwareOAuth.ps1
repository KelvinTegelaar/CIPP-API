function Invoke-CIPPStandardEnableHardwareOAuth {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authenticationmethodspolicy/authenticationMethodConfigurations/HardwareOath' -tenantid $Tenant
    $State = if ($CurrentInfo.state -eq 'enabled') { $true } else { $false }

    If ($Settings.remediate -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'HardwareOAuth Support is already enabled.' -sev Info
        } else {
            Set-CIPPAuthenticationPolicy -Tenant $tenant -APIName 'Standards' -AuthenticationMethodId 'HardwareOath' -Enabled $true
        }
    }

    if ($Settings.alert -eq $true) {

        if ($State) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'HardwareOAuth Support is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'HardwareOAuth Support is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'EnableHardwareOAuth' -FieldValue $State -StoreAs bool -Tenant $tenant
    }
}

