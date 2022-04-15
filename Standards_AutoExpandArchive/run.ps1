param($tenant)

try {
    New-ExoRequest -tenantid $Tenant -cmdlet "Set-OrganizationConfig" -cmdParams @{AutoExpandingArchive = $true }
    Log-request -API "Standards" -tenant $tenant -message "Added Auto Expanding Archive." -sev Info

}
catch {
    Log-request -API "Standards" -tenant $tenant -message "Failed to apply Auto Expanding Archives Error: $($_.exception.message)" -sev Error
}