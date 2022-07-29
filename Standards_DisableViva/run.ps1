param($tenant)

try {
    $MailboxesNoArchive = (New-ExoRequest -tenantid $tenant -cmdlet "get-mailbox" -cmdparams @{ Filter = 'RecipientTypeDetails -Eq "UserMailbox"' }) | ForEach-Object {
        (New-ExoRequest -tenantid $tenant -cmdlet "Set-UserBriefingConfig" -cmdparams @{ Identity = $_.UserPrincipalName; Enabled = $false })
    }
    Write-LogMessage -API "Standards" -tenant $tenant -message "Disable daily Viva reports" -sev Info
    
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to disable Viva for all users Error: $($_.exception.message)" -sev Error
}