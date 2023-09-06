param($tenant)
try {
  Write-LogMessage -API "Standards" -tenant $tenant -message "SSPR standard is no longer available" -sev Error
}
catch {
  Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to enable SSPR $($_.exception.message)" -sev "Error"
}