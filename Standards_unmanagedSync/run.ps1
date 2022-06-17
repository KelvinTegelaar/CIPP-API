param($tenant)

try {
    $body = '{"isUnmanagedSyncAppForTenantRestricted": false}'
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Log-request -API "Standards" -tenant $tenant -message  "Disabled Sync for unmanaged devices" -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to disable Sync for unmanaged devices: $($_.exception.message)" -sev Error
}