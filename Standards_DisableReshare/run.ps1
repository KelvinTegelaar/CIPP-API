param($tenant)

try {
    $body = '{"isResharingByExternalUsersEnabled": false}'
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Log-request -API "Standards" -tenant $tenant -message  "Disabled guests from resharing files" -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to disable guests from resharing files: $($_.exception.message)" -sev Error
}