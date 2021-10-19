param($tenant)

try {
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($tenant)/Mailbox" -Tenantid $tenant -scope ExchangeOnline | Where-Object -propert RecipientTypeDetails -EQ "SharedMailbox") | ForEach-Object {
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ObjectKey)" -type "PATCH" -body '{"accountEnabled":"false"}' -tenantid $tenant
    }
    Log-request -API "Standards" -tenant $tenant -message "Unified Audit Log Enabled." -sev Info

}
catch {
    Log-request -API "Standards" -tenant $tenant -message "Failed to apply Unified Audit Log. Error: $($_.exception.message)" -sev Error
}