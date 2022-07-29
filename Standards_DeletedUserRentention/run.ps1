param($tenant)

try {
    $body = '{"deletedUserPersonalSiteRetentionPeriodInDays": 365}'
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type PATCH -Body $body -ContentType "application/json"

    Write-LogMessage -API "Standards" -tenant $tenant -message  "Set deleted user rentention of OneDrive to 1 year" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set deleted user rentention of OneDrive to 1 year: $($_.exception.message)" -sev Error
}