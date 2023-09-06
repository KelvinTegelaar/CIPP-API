param($tenant)

try {
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet "Get-DkimSigningConfig") | Where-Object -Property Enabled -EQ $false | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet "New-DkimSigningConfig" -cmdparams @{ KeySize = 2048; DomainName = $_.Identity; Enabled = $true } -useSystemMailbox $true)
    }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Enabled DKIM Setup" -sev Info
    
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to enable DKIM. Error: $($_.exception.message)" -sev Error
}