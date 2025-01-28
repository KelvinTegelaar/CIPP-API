function Invoke-CIPPStandardDelegateSentItems {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DelegateSentItems
    .SYNOPSIS
        (Label) Set mailbox Sent Items delegation (Sent items for shared mailboxes)
    .DESCRIPTION
        (Helptext) Sets emails sent as and on behalf of shared mailboxes to also be stored in the shared mailbox sent items folder
        (DocsDescription) This makes sure that e-mails sent from shared mailboxes or delegate mailboxes, end up in the mailbox of the shared/delegate mailbox instead of the sender, allowing you to keep replies in the same mailbox as the original e-mail.
    .NOTES
        CAT
            Exchange Standards
        TAG
            "mediumimpact"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        POWERSHELLEQUIVALENT
            Set-Mailbox
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/exchange-standards#medium-impact
    #>

    param($Tenant, $Settings)
    #$Rerun -Type Standard -Tenant $Tenant -API 'DelegateSentItems' -Settings $Settings


    # Backwards compatibility for Pre 7.0.5
    if ([string]::IsNullOrWhiteSpace($Settings.IncludeUserMailboxes)) {
        $Settings.IncludeUserMailboxes = $true
    }

    if ($Settings.IncludeUserMailboxes -eq $true) {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = @('UserMailbox', 'SharedMailbox') } -Select 'Identity,UserPrincipalName,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled' |
            Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false }
    } else {
        $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = @('SharedMailbox') } -Select 'Identity,UserPrincipalName,MessageCopyForSendOnBehalfEnabled,MessageCopyForSentAsEnabled' |
            Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false }
    }


    Write-Host "Mailboxes: $($Mailboxes.Count)"
    If ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'

        if ($Mailboxes) {
            try {
                $Request = $Mailboxes | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{Identity = $_.UserPrincipalName ; MessageCopyForSendOnBehalfEnabled = $true; MessageCopyForSentAsEnabled = $true }
                        }
                    }
                }
                $BatchResults = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($Request)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-CippException -Exception $_.error
                        Write-Host "Failed to apply Delegate Sent Items Style to $($_.target) Error: $($ErrorMessage.NormalizedError)"
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply Delegate Sent Items Style to $($_.error.target) Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                    }
                }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Delegate Sent Items Style applied for $($Mailboxes.Count - $BatchResults.Error.Count) mailboxes" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to apply Delegate Sent Items Style. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Delegate Sent Items Style already enabled.' -sev Info

        }
    }
    if ($Settings.alert -eq $true) {
        if ($null -eq $Mailboxes) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Delegate Sent Items Style is enabled for all mailboxes' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Delegate Sent Items Style is not enabled for $($Mailboxes.Count) mailboxes" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $Filtered = $Mailboxes | Select-Object -Property UserPrincipalName, MessageCopyForSendOnBehalfEnabled, MessageCopyForSentAsEnabled
        Add-CIPPBPAField -FieldName 'DelegateSentItems' -FieldValue $Filtered -StoreAs json -Tenant $Tenant
    }
}
