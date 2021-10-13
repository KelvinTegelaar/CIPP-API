param($tenant)

try {
    $SecureDefaultsState = (New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy" -tenantid $tenant)
  
    if ($SecureDefaultsState.IsEnabled -ne $true) {
        write-host "Secure Defaults is disabled. Enabling for $tenant" -ForegroundColor Yellow
        $body = '{ "isEnabled": true }'
    (Invoke-RestMethod -Uri "$baseuri/policies/identitySecurityDefaultsEnforcementPolicy" -Headers $Header -Method patch -Body $body -ContentType "application/json")
    }
    Log-request "Standards API: $($Tenant) Security Defaults Enabled." -sev Info
}
catch {
    Log-request "Standards API: $($Tenant) Failed to enable Security Defaults Error: $($_.exception.message)"
}