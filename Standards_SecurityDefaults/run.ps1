param($tenant)

try {
    $SecureDefaultsState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy" -tenantid $tenant)
  
    if ($SecureDefaultsState.IsEnabled -ne $true) {
        Write-Host "Secure Defaults is disabled. Enabling for $tenant" -ForegroundColor Yellow
        $body = '{ "isEnabled": true }'
    (Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy" -Headers $Header -Method patch -Body $body -ContentType "application/json")
    }
    Log-request -API "Standards" -tenant $tenant -message "Standards API: Security Defaults Enabled." -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to enable Security Defaults Error: $($_.exception.message)"
}
