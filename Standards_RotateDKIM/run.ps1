param($tenant)

try {
    $DKIM = (New-ExoRequest -tenantid $tenant -cmdlet "Get-DkimSigningConfig") | Where-Object { $_.Selector1KeySize -EQ 1024 -and $_.Enabled -eq $true } | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet "Rotate-DkimSigningConfig" -cmdparams @{ KeySize = 2048; Identity = $_.Identity } -useSystemMailbox $true)
    }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Rotated DKIM" -sev Info
    
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to rotate DKIM Error: $($_.exception.message)" -sev Error
}