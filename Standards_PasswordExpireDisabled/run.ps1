param($tenant)
try {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/?`$top=999&`$select=userPrincipalName,passwordPolicies" -tenantid $Tenant | Where-Object -Property passwordPolicies -EQ $null | ForEach-Object {
        New-GraphPostRequest -type Patch -tenantid $tenant -uri "https://graph.microsoft.com/beta/users/$($_.id)" -body '{"passwordPolicies": "DisablePasswordExpiration"}'
    }
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Disabled Password Expiration" -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to disable Password Expiration. Error: $($_.exception.message)" -sev Error
}