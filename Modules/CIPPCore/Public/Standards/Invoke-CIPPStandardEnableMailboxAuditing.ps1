function Invoke-CIPPStandardEnableMailboxAuditing {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $AuditState = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').AuditDisabled

    if ($Settings.remediate) {
        if ($AuditState) {
            # Enable tenant level mailbox audit
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{AuditDisabled = $false } -useSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Tenant level mailbox audit enabled' -sev Info
                $LogMessage = 'Tenant level mailbox audit enabled. '
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable tenant level mailbox audit. Error: $($_.exception.message)" -sev Error
            }
        } else {
            $LogMessage = 'Tenant level mailbox audit already enabled. '
        }

        # Check for mailbox audit on all mailboxes. Enable for all that it's not enabled for
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{filter = "auditenabled -eq 'False'" } -useSystemMailbox $true -Select 'AuditEnabled,UserPrincipalName' 
        $Mailboxes | ForEach-Object {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $_.UserPrincipalName; AuditEnabled = $true } -Anchor $_.UserPrincipalName 
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "User level mailbox audit enabled for $($_.UserPrincipalName)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable user level mailbox audit for $($_.UserPrincipalName). Error: $($_.exception.message)" -sev Error
            }
        }

        # Disable audit bypass for all mailboxes that have it enabled
        
        $BypassMailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-MailboxAuditBypassAssociation' -select 'GUID, AuditBypassEnabled, Name' -useSystemMailbox $true | Where-Object { $_.AuditBypassEnabled -eq $true }
        $BypassMailboxes | ForEach-Object {
            try {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxAuditBypassAssociation' -cmdParams @{Identity = $_.Guid; AuditBypassEnabled = $false } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Mailbox audit bypass disabled for $($_.Name)" -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable mailbox audit bypass for $($_.Name). Error: $($_.exception.message)" -sev Error
            }
        }

        $LogMessage = if ($Mailboxes.Count -eq 0 -and $BypassMailboxes.Count -eq 0) {
            # Make log message smaller if both are already in the desired state
            'User level mailbox audit already enabled and mailbox audit bypass already disabled for all mailboxes'
        } else {
            if ($Mailboxes.Count -eq 0) {
                'User level mailbox audit already enabled for all mailboxes. '
            }
            if ($BypassMailboxes.Count -eq 0) {
                'Mailbox audit bypass already disabled for all mailboxes'
            }    
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
        $AuditState = -not $AuditState
        Add-CIPPBPAField -FieldName 'MailboxAuditingEnabled' -FieldValue [bool]$AuditState -StoreAs bool -Tenant $Tenant
    }
    
}