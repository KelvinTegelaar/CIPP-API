param($tenant)
if ((Test-Path ".\Cache_Standards\$($Tenant).Standards.json")) {
    $Setting = (Get-Content ".\Cache_Standards\$($Tenant).Standards.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).standards.ExcludedfileExt
}

if (!$Setting) { $Setting = (Get-Content ".\Cache_Standards\AllTenants.Standards.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue).standards.ExcludedfileExt }

try {
    $Exts = $Setting.ext -split ','
    $body = ConvertTo-Json -InputObject @{ excludedFileExtensionsForSyncApp = @($Exts) }
    New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/admin/sharepoint/settings" -AsApp $true -Type patch -Body $body -ContentType "application/json"
    Log-request -API "Standards" -tenant $tenant -message  "Added $($Setting.ext) to excluded synced files" -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message  "Failed to add $($Setting.ext) to excluded synced files: $($_.exception.message)" -sev Error
}