function Invoke-CIPPStandardDisableSharedMailbox {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $UserList = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$top=999&$filter=accountEnabled eq true' -Tenantid $tenant -scope 'https://graph.microsoft.com/.default' 
    $SharedMailboxList = (New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$($Tenant)/Mailbox" -Tenantid $tenant -scope ExchangeOnline | Where-Object { $_.RecipientTypeDetails -EQ 'SharedMailbox' -or $_.RecipientTypeDetails -eq 'SchedulingMailbox' -and $_.UserPrincipalName -in $UserList.UserPrincipalName })

    If ($Settings.remediate -eq $true) {

        if ($SharedMailboxList) {
            $SharedMailboxList | ForEach-Object {
                try {
                    New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$($_.ObjectKey)" -type PATCH -body '{"accountEnabled":"false"}' -tenantid $tenant
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "AAD account for shared mailbox $($_.DisplayName) disabled." -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable AAD account for shared mailbox. Error: $ErrorMessage" -sev Error
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
