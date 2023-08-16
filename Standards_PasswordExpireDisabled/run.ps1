param($tenant)
try {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/domains" -tenantid $Tenant | Where-Object -Property passwordValidityPeriodInDays -NE '2147483647' | ForEach-Object {
        New-GraphPostRequest -type Patch -tenantid $Tenant -uri "https://graph.microsoft.com/beta/domains/$($_.id)" -body '{"passwordValidityPeriodInDays": 2147483647 }'
    }
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Disabled Password Expiration" -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to disable Password Expiration. Error: $($_.exception.message)" -sev Error
}