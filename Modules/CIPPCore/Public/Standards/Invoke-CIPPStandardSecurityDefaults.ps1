function Invoke-CIPPStandardSecurityDefaults {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $tenant)

    If ($Settings.remediate -eq $true) {
        if ($SecureDefaultsState.IsEnabled -ne $true) {
            try {
                Write-Host "Secure Defaults is disabled. Enabling for $tenant" -ForegroundColor Yellow
                $body = '{ "isEnabled": true }'
                $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -Type patch -Body $body -ContentType 'application/json'

                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Enabled Security Defaults.' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Security Defaults. Error: $($_.exception.message)" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is already enabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($SecureDefaultsState.IsEnabled -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is enabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Security Defaults is not enabled.' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'SecurityDefaults' -FieldValue $SecureDefaultsState.IsEnabled -StoreAs bool -Tenant $tenant
    }
}
