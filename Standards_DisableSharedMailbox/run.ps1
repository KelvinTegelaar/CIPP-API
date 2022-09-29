param($tenant)

try {
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenant)/Mailbox" -Tenantid $tenant -scope ExchangeOnline | Where-Object { $_.RecipientTypeDetails -EQ "SharedMailbox" -or $_.RecipientTypeDetails -eq 'SchedulingMailbox' }) | ForEach-Object {
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ObjectKey)" -type "PATCH" -body '{"accountEnabled":"false"}' -tenantid $tenant
    }
    Write-LogMessage -API "Standards" -tenant $tenant -message "AAD Accounts for shared mailboxes disabled." -sev Info
    
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message "Failed to disable AAD accounts for shared mailboxes. Error: $($_.exception.message)" -sev Error
}