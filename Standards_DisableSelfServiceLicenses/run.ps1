param($tenant)

try {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to disable License Buy Self Service: $($_.exception.message)" -sev Error
    
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to disable License Buy Self Service: $($_.exception.message)" -sev Error
}