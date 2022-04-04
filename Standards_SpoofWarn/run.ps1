param($tenant)

try {
    New-ExoRequest -tenantid $Tenant -cmdlet "Set-ExternalInOutlook" -cmdParams @{ Enabled = $true; }
    Log-request -API "Standards" -tenant $tenant -message "Spoofing warnings enabled." -sev Info

}
catch {
    Log-request -API "Standards" -tenant $tenant -message "Could not enabled spoofing warnings. Error: $($_.exception.message)" -sev Error
}