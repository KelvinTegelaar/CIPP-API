function Invoke-CIPPStandardSafeSendersDisable {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    If ($Settings.remediate -eq $true) {
        try {
            $Mailboxes = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-Mailbox' | ForEach-Object {
                try {
                    $username = $_.UserPrincipalName
                    New-ExoRequest -tenantid $Tenant -cmdlet 'Set-MailboxJunkEmailConfiguration' -cmdParams @{Identity = $_.GUID ; TrustedRecipientsAndDomains = $null } -anchor $username
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Could not disbale SafeSenders list for $($username): $($_.Exception.message)" -sev Warn
                }
            }
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Safe Senders disabled' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable SafeSenders. Error: $($_.exception.message)" -sev Error
        }
    }

}
