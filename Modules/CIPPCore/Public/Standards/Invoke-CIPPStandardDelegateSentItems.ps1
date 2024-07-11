function Invoke-CIPPStandardDelegateSentItems {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DelegateSentItems
    .CAT
    Exchange Standards
    .TAG
    "mediumimpact"
    .HELPTEXT
    Sets emails sent as and on behalf of shared mailboxes to also be stored in the shared mailbox sent items folder
    .DOCSDESCRIPTION
    This makes sure that e-mails sent from shared mailboxes or delegate mailboxes, end up in the mailbox of the shared/delegate mailbox instead of the sender, allowing you to keep replies in the same mailbox as the original e-mail.
    .ADDEDCOMPONENT
    .LABEL
    Set mailbox Sent Items delegation (Sent items for shared mailboxes)
    .IMPACT
    Medium Impact
    .POWERSHELLEQUIVALENT
    Set-Mailbox
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    Sets emails sent as and on behalf of shared mailboxes to also be stored in the shared mailbox sent items folder
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)
    $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = @('UserMailbox', 'SharedMailbox') } |
        Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false }
    Write-Host "Mailboxes: $($Mailboxes.count)"
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
                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray @($Request)
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to apply Delegate Sent Items Style to $($_.target) Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Delegate Sent Items Style to $($_.error.target) Error: $ErrorMessage" -sev Error
                    }
                }
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Delegate Sent Items Style applied for $($Mailboxes.count - $BatchResults.Error.Count) mailboxes" -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Delegate Sent Items Style. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style already enabled.' -sev Info

        }
    }
    if ($Settings.alert -eq $true) {
        if ($null -eq $Mailboxes) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style is enabled for all mailboxes' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Delegate Sent Items Style is not enabled for $($Mailboxes.count) mailboxes" -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        $Filtered = $Mailboxes | Select-Object -Property UserPrincipalName, MessageCopyForSendOnBehalfEnabled, MessageCopyForSentAsEnabled
        Add-CIPPBPAField -FieldName 'DelegateSentItems' -FieldValue $Filtered -StoreAs json -Tenant $tenant
    }
}




