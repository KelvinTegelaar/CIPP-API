param($tenant)
if ((Test-Path ".\Cache_Standards\$($Tenant).Standards.json")) {
    $Setting = (Get-Content ".\Cache_Standards\$($Tenant).Standards.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).standards.sharingCapability
}

if (!$Setting) { $Setting = (Get-Content ".\Cache_Standards\AllTenants.Standards.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).standards.sharingCapability }

try {
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body "{`"sharingCapability`":`"$($Setting.Level)`"}" -ContentType "application/json"
    Log-request -API "Standards" -tenant $tenant -message  "Set sharing level to $($Setting.level)" -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to set sharing level to $($Setting.level): $($_.exception.message)" -sev Error
}