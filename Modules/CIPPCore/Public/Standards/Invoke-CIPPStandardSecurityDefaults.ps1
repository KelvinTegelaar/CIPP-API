function Invoke-SecurityDefaults {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $tenant)
    If ($Settings.Remediate) {
        try {
            if ($SecureDefaultsState.IsEnabled -ne $true) {
                Write-Host "Secure Defaults is disabled. Enabling for $tenant" -ForegroundColor Yellow
                $body = '{ "isEnabled": true }'
               (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -Type patch -Body $body -ContentType 'application/json')
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Standards API: Security Defaults Enabled.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Security Defaults Error: $($_.exception.message)" -sev 'Error'
        }
    }
    if ($Settings.Alert) {
        if ($SecureDefaultsState.IsEnabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is not enabled.' -sev Alert
        }
    }
}
