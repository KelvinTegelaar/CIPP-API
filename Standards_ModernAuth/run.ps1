param($tenant)

try {
    $currentStatus = New-ClassicAPIGetRequest -Uri "https://admin.microsoft.com/admin/api/services/apps/modernAuth" -TenantID $tenant
    $currentStatus.EnableModernAuth = $true
    $ModernAuthRequest = New-ClassicAPIPostRequest -Uri 'https://admin.microsoft.com/admin/api/services/apps/modernAuth' -Body ($currentStatus | ConvertTo-Json) -Method POST -TenantID $tenant
    Log-request -API "Standards" -tenant $tenant -message "Modern Authentication enabled." -sev Info
}
catch {
    Log-request -API "Standards" -tenant $tenant -message "Failed to enable Modern Authentication. Error: $($_.exception.message)" -sev "Error"
}