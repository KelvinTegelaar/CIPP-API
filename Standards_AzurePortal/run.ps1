param($tenant)

Write-LogMessage -API "Standards" -tenant $tenant -message "Azure Portal disablement is no longer functional. Please remove this standard." -sev Error
