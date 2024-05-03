function Set-CIPPForwarding {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $userid,
        $forwardingSMTPAddress,
        $tenantFilter,
        $username,
        $ExecutingUser,
        $APIName = 'Forwarding',
        $Forward,
        $KeepCopy,
        $Disable
    )

    try {
        if (!$username) { $username = $userid }
        if ($PSCmdlet.ShouldProcess($username, 'Set forwarding')) {
            $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $userid; ForwardingSMTPAddress = $forwardingSMTPAddress; ForwardingAddress = $Forward ; DeliverToMailboxAndForward = [bool]$KeepCopy } -Anchor $username
        }
        if (!$Disable) {
            $Message = "Forwarding all email for $username to $Forward"
        } else {
            $Message = "Disabled forwarding for $username"
        }
        Write-LogMessage -user $ExecutingUser -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
        return "Could not add forwarding for $($username). Error: $($_.Exception.Message)"
    }
}
