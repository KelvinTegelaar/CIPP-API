function Set-CIPPForwarding {
    <#
    .SYNOPSIS
    Set forwarding for a user mailbox.

    .DESCRIPTION
    Set forwarding for a user mailbox.

    .PARAMETER userid
    User ID to set forwarding for.

    .PARAMETER forwardingSMTPAddress
    SMTP address to forward to.

    .PARAMETER tenantFilter
    Tenant to manage for forwarding.

    .PARAMETER username
    Username to manage for forwarding.

    .PARAMETER ExecutingUser
    CIPP user executing the command.

    .PARAMETER APIName
    Name of the API executing the command.

    .PARAMETER Forward
    Forwarding address.

    .PARAMETER KeepCopy
    Keep a copy of the email.

    .PARAMETER Disable
    Disable forwarding.

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$userid,
        [string]$forwardingSMTPAddress,
        [string]$tenantFilter,
        [string]$username,
        [string]$ExecutingUser,
        [string]$APIName = 'Forwarding',
        [string]$Forward,
        [bool]$KeepCopy,
        [bool]$Disable
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
