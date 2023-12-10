function Invoke-CIPPStandardDisableSharedMailbox {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($Tenant)/Mailbox?`$filter=ExchangeUserAccountControl ne 'accountdisabled'" -Tenantid $tenant -scope ExchangeOnline | Where-Object { $_.RecipientTypeDetails -EQ 'SharedMailbox' -or $_.RecipientTypeDetails -eq 'SchedulingMailbox' })
    If ($Settings.remediate) {
        try {
            $SharedMailboxList | ForEach-Object {
                New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ObjectKey)" -type 'PATCH' -body '{"accountEnabled":"false"}' -tenantid $tenant
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'AAD Accounts for shared mailboxes disabled.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable AAD accounts for shared mailboxes. Error: $($_.exception.message)" -sev Error
        }
    }
    if ($Settings.alert) {

        if ($SharedMailboxList) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Shared mailboxes with enabled accounts: $($SharedMailboxList.count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No AAD accounts enables for shared mailboxes.' -sev Info
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'DisableSharedMailbox' -FieldValue $SharedMailboxList -StoreAs json -Tenant $tenant
    }
}
