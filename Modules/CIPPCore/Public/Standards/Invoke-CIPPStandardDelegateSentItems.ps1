function Invoke-CIPPStandardDelegateSentItems {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = @('UserMailbox', 'SharedMailbox') } | 
        Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false }

    If ($Settings.remediate -eq $true) {

        if ($Mailboxes) {
            try {
                $Request = $mailboxes | ForEach-Object {
                    @{
                        CmdletInput = @{
                            CmdletName = 'Set-Mailbox'
                            Parameters = @{Identity = $_.UserPrincipalName ; MessageCopyForSendOnBehalfEnabled = $true; MessageCopyForSentAsEnabled = $true }
                        }
                    }
                }
                $BatchResults = New-ExoBulkRequest -tenantid $tenant -cmdletArray $Request
                $BatchResults | ForEach-Object {
                    if ($_.error) {
                        $ErrorMessage = Get-NormalizedError -Message $_.error
                        Write-Host "Failed to apply Delegate Sent Items Style to $($_.target) Error: $ErrorMessage"
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Delegate Sent Items Style to $($_.error.target) Error: $ErrorMessage" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Delegate Sent Items Style. Error: $ErrorMessage" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style already enabled.' -sev Info

        }
    }
    if ($Settings.alert -eq $true) {
        if ($Mailboxes) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Delegate Sent Items Style is not enabled for $($mailboxes.count) mailboxes" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style is enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $Filtered = $Mailboxes | Select-Object -Property UserPrincipalName, MessageCopyForSendOnBehalfEnabled, MessageCopyForSentAsEnabled
        Add-CIPPBPAField -FieldName 'DelegateSentItems' -FieldValue $Filtered -StoreAs json -Tenant $tenant
    }
}
