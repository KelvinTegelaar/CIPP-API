param($tenant)
#Write-LogMessage -API "SecurityBaselines" -tenant $tenant -message "SecurityBaselines_All called at $((Get-Date).tofiletime())" -sev Info
Write-Output $tenant.defaultDomainName

