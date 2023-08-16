param($tenant)

try {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Passwordless with number matching is now enabled by default." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to enable passwordless with Number Matching. Error: $($_.exception.message)" -sev "Error"
}