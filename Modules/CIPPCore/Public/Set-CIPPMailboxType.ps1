function Set-CIPPMailboxType {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = "Mailbox Conversion",
        $TenantFilter,
        [Parameter()]
        [ValidateSet('shared', 'Regular', 'Room', 'Equipment')]$MailboxType
    )

    try {
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-mailbox" -cmdParams @{Identity = $userid; type = $MailboxType } -Anchor $username
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Converted $($username) to a $MailboxType mailbox" -Sev "Info" -tenant $TenantFilter
        if (!$username) { $username = $userid }
        return "Converted $($username) to a $MailboxType mailbox"
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not convert $username to $MailboxType mailbox" -Sev "Error" -tenant $TenantFilter
        return  "Could not convert $($username) to a $MailboxType mailbox. Error: $($_.Exception.Message)"
    }
}
