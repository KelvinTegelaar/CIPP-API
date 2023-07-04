function Set-CIPPForwarding {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $username,
        $ExecutingUser,
        $APIName = "Forwarding",
        $Forward,
        $KeepCopy
    )

    try {
        $permissions = New-ExoRequest -tenantid $tenantFilter -cmdlet "Set-mailbox" -cmdParams @{Identity = $userid; ForwardingAddress = $Forward ; DeliverToMailboxAndForward = [bool]$KeepCopy } -Anchor $username
        "Forwarding all email for $username to $Forward"
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Set Forwarding for $($username) to $Forward" -Sev "Info" -tenant $TenantFilter
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add forwarding for $($username)" -Sev "Error" -tenant $TenantFilter
        return "Could not add forwarding for $($username). Error: $($_.Exception.Message)"
    }
}
