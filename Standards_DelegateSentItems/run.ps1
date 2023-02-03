param($tenant)

try {
    $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet "Get-Mailbox" -cmdParams @{ RecipientTypeDetails = @("UserMailbox", "SharedMailbox") } | Where-Object { $_.MessageCopyForSendOnBehalfEnabled -eq $false -or $_.MessageCopyForSentAsEnabled -eq $false } | ForEach-Object {
        try {
            $username = $_.UserPrincipalName
            New-ExoRequest -tenantid $Tenant -cmdlet "set-mailbox" -cmdParams @{Identity = $_.GUID ; MessageCopyForSendOnBehalfEnabled = $True; MessageCopyForSentAsEnabled = $True } -anchor $username
        }
        catch {
            Write-LogMessage  -API "Standards" -tenant $tenant -message "Could not enable delegate sent item style for $($username): $($_.Exception.message)" -sev Warn
        }
    }   
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Delegate Sent Items Style enabled." -sev Info
}
catch {
    Write-LogMessage  -API "Standards" -tenant $tenant -message "Failed to apply Delegate Sent Items Style. Error: $($_.exception.message)" -sev Error
}