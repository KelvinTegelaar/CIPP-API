function Invoke-CIPPStandardEnableMailboxAuditing {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $AuditState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AuditDisabled
    if ( $Settings.remediate) {
        if ($AuditState) {
            # Enable tenant level mailbox audit
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{AuditDisabled = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit enabled' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable tenant level mailbox audit. Error: $($_.exception.message)" -sev Error
            }
        } else {
            $LogMessage = 'Tenant level mailbox audit already enabled. '
        }

        # check for mailbox audit on all mailboxes. Enabled for all that it's not enabled for
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ResultSize = 'Unlimited' } | Where-Object { $_.AuditEnabled -ne $true }
        $Mailboxes | ForEach-Object {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $_.UserPrincipalName; AuditEnabled = $true } -Anchor $_.UserPrincipalName 
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "User level mailbox audit enabled for $($_.UserPrincipalName)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable user level mailbox audit for $($_.UserPrincipalName). Error: $($_.exception.message)" -sev Error
            }
        }
        if ($Mailboxes.Count -eq 0) {
            $LogMessage += 'User level mailbox audit already enabled for all mailboxes'
        }
        Write-LogMessage -API 'Standards' -tenant $Tenant -message $LogMessage -sev Info
    }

    if ($Settings.alert) {
        if ($AuditState) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit is not enabled' -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit is enabled' -sev Info
        }
    }
    if ($Settings.report) {
        Add-CIPPBPAField -FieldName 'MailboxAuditingEnabled' -FieldValue [bool]$AuditState -StoreAs bool -Tenant $Tenant
    }
    
}