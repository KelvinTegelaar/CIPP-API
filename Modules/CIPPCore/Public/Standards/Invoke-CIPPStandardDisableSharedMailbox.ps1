function Invoke-CIPPStandardDisableSharedMailbox {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($Tenant)/Mailbox?`$filter=ExchangeUserAccountControl ne 'accountdisabled'" -Tenantid $tenant -scope ExchangeOnline | Where-Object { $_.RecipientTypeDetails -EQ 'SharedMailbox' -or $_.RecipientTypeDetails -eq 'SchedulingMailbox' })

    If ($Settings.remediate -eq $true) {
        if ($SharedMailboxList) {
            $SharedMailboxList | ForEach-Object {
                try {
                    New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ObjectKey)" -type PATCH -body '{"accountEnabled":"false"}' -tenantid $tenant
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "AAD account for shared mailbox $($_.DisplayName) disabled." -sev Info
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable AAD account for shared mailbox. Error: $($_.exception.message)" -sev Error
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All AAD accounts for shared mailboxes are already disabled.' -sev Info
        }
    }

    if ($Settings.alert -eq $true) {

        if ($SharedMailboxList) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Shared mailboxes with enabled accounts: $($SharedMailboxList.Count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All AAD accounts for shared mailboxes are disabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DisableSharedMailbox' -FieldValue $SharedMailboxList -StoreAs json -Tenant $tenant
    }
}
