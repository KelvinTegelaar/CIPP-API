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
        $KeepCopy,
        [bool]$Disable
    )


    try {
        if (!$username) { $username = $userid }
        if ($PSCmdlet.ShouldProcess($username, 'Set forwarding')) {
            if ($Disable -eq $true) {
                Write-Output "Disabling forwarding for $username"
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $userid; ForwardingSMTPAddress = $null; ForwardingAddress = $null ; DeliverToMailboxAndForward = $false } -Anchor $username
                $Message = "Disabled forwarding for $username"
            } elseif ($Forward) {
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $userid; ForwardingSMTPAddress = $null; ForwardingAddress = $Forward ; DeliverToMailboxAndForward = $KeepCopy } -Anchor $username
                $Message = "Forwarding all email for $username to Internal Address $Forward and keeping a copy set to $KeepCopy"
            } elseif ($forwardingSMTPAddress) {
                $null = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Set-mailbox' -cmdParams @{Identity = $userid; ForwardingSMTPAddress = $forwardingSMTPAddress; ForwardingAddress = $null ; DeliverToMailboxAndForward = $KeepCopy } -Anchor $username
                $Message = "Forwarding all email for $username to External Address $ForwardingSMTPAddress and keeping a copy set to $KeepCopy"
            }
        }
        Write-LogMessage -user $ExecutingUser -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add forwarding for $($username)" -Sev 'Error' -tenant $TenantFilter
        return "Could not add forwarding for $($username). Error: $($_.Exception.Message)"
    }
}
