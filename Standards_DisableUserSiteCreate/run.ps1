param($tenant)

try {
    $body = '{"isSiteCreationEnabled": false}'
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Disabled standard users from creating sites" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable standard users from creating sites: $($_.exception.message)" -sev Error
}