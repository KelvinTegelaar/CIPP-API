param($tenant)

try {
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/reportSettings" -Type patch -Body '{"displayConcealedNames": false}' -ContentType "application/json"
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Anonymous Reports Disabled." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to disable anonymous reports. Error: $($_.exception.message)"
}