function Set-CIPPForwarding {
    [CmdletBinding()]
    param(
        $userid,
        $forwardingSMTPAddress,
        $tenantFilter,
        $username,
        $ExecutingUser,
        $APIName = "Forwarding",
        $Forward,
        $KeepCopy,
        $Disable
    )

    try {
        if (!$username) { $username = $userid }
        $permissions = New-ExoRequest -tenantid $tenantFilter -cmdlet "Set-mailbox" -cmdParams @{Identity = $userid; ForwardingSMTPAddress = $forwardingSMTPAddress; ForwardingAddress = $Forward ; DeliverToMailboxAndForward = [bool]$KeepCopy } -Anchor $username
        if (!$Disable) { "Forwarding all email for $username to $Forward" } else { "Disabled forwarding for $username" }
    
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Forwarding for $($username) to $Forward" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add forwarding for $($username)" -Sev "Error" -tenant $TenantFilter
        return "Could not add forwarding for $($username). Error: $($_.Exception.Message)"
    }
}
