function Invoke-CIPPStandardMailboxRecipientLimits {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) MailboxRecipientLimits
    .SYNOPSIS
        (Label) Set Mailbox Recipient Limits
    .DESCRIPTION
        (Helptext) Sets the maximum number of recipients that can be specified in the To, Cc, and Bcc fields of a message for all mailboxes in the tenant.
        (DocsDescription) This standard configures the recipient limits for all mailboxes in the tenant. The recipient limit determines the maximum number of recipients that can be specified in the To, Cc, and Bcc fields of a message. This helps prevent spam and manage email flow.
    .NOTES
        CAT
            Exchange Standards
        TAG
        ADDEDCOMPONENT
            {"type":"number","name":"standards.MailboxRecipientLimits.RecipientLimit","label":"Recipient Limit","defaultValue":500}
        IMPACT
            Low Impact
        ADDEDDATE
            2025-05-28
        POWERSHELLEQUIVALENT
            Set-Mailbox -RecipientLimits
        RECOMMENDEDBY
            "CIPP"
    #>

    param($Tenant, $Settings)

    # Input validation
    if ([Int32]$Settings.RecipientLimit -lt 0 -or [Int32]$Settings.RecipientLimit -gt 10000) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message 'MailboxRecipientLimits: Invalid RecipientLimit parameter set. Must be between 0 and 10000.' -sev Error
        return
    }

    # Get all mailboxes in the tenant
    $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ResultSize = 'Unlimited' }

    # Check which mailboxes need to be updated
    $MailboxesToUpdate = $Mailboxes | Where-Object { $_.RecipientLimits -ne $Settings.RecipientLimit }

    # Remediation
    if ($Settings.remediate -eq $true) {
        if ($MailboxesToUpdate.Count -gt 0) {
            try {
                foreach ($Mailbox in $MailboxesToUpdate) {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdParams @{
                        Identity        = $Mailbox.Identity
                        RecipientLimits = $Settings.RecipientLimit
                    }
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set recipient limits to $($Settings.RecipientLimit) for $($MailboxesToUpdate.Count) mailboxes" -sev Info
            }
            catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not set recipient limits. $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
        else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All mailboxes already have the correct recipient limit of $($Settings.RecipientLimit)" -sev Info
        }
    }

    # Alert
    if ($Settings.alert -eq $true) {
        if ($MailboxesToUpdate.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All mailboxes have the correct recipient limit of $($Settings.RecipientLimit)" -sev Info
        }
        else {
            Write-StandardsAlert -message "Found $($MailboxesToUpdate.Count) mailboxes with incorrect recipient limits" -object $MailboxesToUpdate -tenant $Tenant -standardName 'MailboxRecipientLimits' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Found $($MailboxesToUpdate.Count) mailboxes with incorrect recipient limits" -sev Info
        }
    }

    # Report
    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'MailboxRecipientLimits' -FieldValue $MailboxesToUpdate -StoreAs json -Tenant $Tenant

        if ($MailboxesToUpdate.Count -eq 0) {
            $FieldValue = $true
        }
        else {
            $FieldValue = $MailboxesToUpdate
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.MailboxRecipientLimits' -FieldValue $FieldValue -Tenant $Tenant
    }
} 