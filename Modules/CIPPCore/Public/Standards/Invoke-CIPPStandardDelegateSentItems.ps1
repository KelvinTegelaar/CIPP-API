function Invoke-CIPPStandardDelegateSentItems {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = @('UserMailbox', 'SharedMailbox') } | Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false } 

    If ($Settings.remediate) {

        if ($Mailboxes) {
            try {
                $Mailboxes | ForEach-Object {
                    try {
                        $username = $_.UserPrincipalName
                        New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $_.GUID ; MessageCopyForSendOnBehalfEnabled = $True; MessageCopyForSentAsEnabled = $True } -anchor $username
                    } catch {
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not enable delegate sent item style for $($username): $($_.Exception.message)" -sev Warn
                    }
                }   
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style enabled.' -sev Info
            } catch {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to apply Delegate Sent Items Style. Error: $($_.exception.message)" -sev Error
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style already enabled.' -sev Info
        
        }
    }
    if ($Settings.alert) {
        if ($Mailboxes) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Delegate Sent Items Style is not enabled for $($mailboxes.count) mailboxes" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Delegate Sent Items Style is enabled' -sev Info
        }
    }

    if ($Settings.report) {
        $Filtered = $Mailboxes | Select-Object -Property UserPrincipalName, MessageCopyForSendOnBehalfEnabled, MessageCopyForSentAsEnabled
        Add-CIPPBPAField -FieldName 'DelegateSentItems' -FieldValue $Filtered -StoreAs json -Tenant $tenant
    }
}
