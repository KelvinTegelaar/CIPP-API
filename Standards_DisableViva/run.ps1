param($tenant)

try {
    $MailboxesNoArchive = (New-ExoRequest -tenantid $tenant -cmdlet "get-mailbox" -cmdparams @{ Filter = 'RecipientTypeDetails -Eq "UserMailbox"' }) | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet "Set-UserBriefingConfig" -cmdparams @{ Identity = $_.UserPrincipalName; Enabled = $false })
    }
    Log-request -API "Standards" -tenant $tenant -message "Enabled Online Archiving for all accounts" -sev Info
    
}
catch {
    Log-request -API "Standards" -tenant $tenant -message "Failed to Enable Online Archiving for all accounts Error: $($_.exception.message)" -sev Error
}