param($tenant)

try {
    New-ExoRequest -tenantid $Tenant -cmdlet "Set-ExternalInOutlook" -cmdParams @{ Enabled = $true; }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Spoofing warnings enabled." -sev Info

}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Could not enabled spoofing warnings. Error: $($_.exception.message)" -sev Error
}