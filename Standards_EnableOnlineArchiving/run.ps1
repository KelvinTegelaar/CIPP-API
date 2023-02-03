param($tenant)

try {
    $MailboxesNoArchive = (New-ExoRequest -tenantid $tenant -cmdlet "get-mailbox" -cmdparams @{ Filter = 'ArchiveGuid -Eq "00000000-0000-0000-0000-000000000000" -AND RecipientTypeDetails -Eq "UserMailbox"' }) | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet "enable-Mailbox" -cmdparams @{ Identity = $_.UserPrincipalName; Archive = $true })
    }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Enabled Online Archiving for all accounts" -sev Info
    
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to Enable Online Archiving for all accounts Error: $($_.exception.message)" -sev Error
}