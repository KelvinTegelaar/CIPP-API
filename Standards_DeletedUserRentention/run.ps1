param($tenant)

try {
    $body = '{"deletedUserPersonalSiteRetentionPeriodInDays": 3650}'
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type PATCH -Body $body -ContentType "application/json"

    Write-LogMessage -API "Standards" -tenant $tenant -message  "Set deleted user rentention of OneDrive to 10 years" -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to set deleted user rentention of OneDrive to 10 years: $($_.exception.message)" -sev Error
}
