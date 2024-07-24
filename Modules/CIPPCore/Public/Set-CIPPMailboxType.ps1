function Set-CIPPMailboxType {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = 'Mailbox Conversion',
        $TenantFilter,
        [Parameter()]
        [ValidateSet('Shared', 'Regular', 'Room', 'Equipment')]$MailboxType
    )

    try {
        if ([string]::IsNullOrWhiteSpace($username)) { $username = $userid }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $userid; Type = $MailboxType } -Anchor $username
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Converted $($username) to a $MailboxType mailbox" -Sev 'Info' -tenant $TenantFilter
        return "Converted $username to a $MailboxType mailbox"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not convert $username to $MailboxType mailbox. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return  "Could not convert $username to a $MailboxType mailbox. Error: $($ErrorMessage.NormalizedError)"
    }
}
