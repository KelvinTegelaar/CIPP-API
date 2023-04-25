param($tenant)
try {
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy" -Type PUT -Body '{ "localAdminPassword":{"isEnabled": true }}' -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "LAPS has been enabled." -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set LAPS: $($_.exception.message)" -sev Error
}