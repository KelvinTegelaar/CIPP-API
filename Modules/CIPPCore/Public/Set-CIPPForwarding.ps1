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

    .PARAMETER Headers
    CIPP HTTP Request headers.

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
        [string]$UserID,
        [string]$ForwardingSMTPAddress,
        [string]$TenantFilter,
        [string]$Username,
        $Headers,
        [string]$APIName = 'Forwarding',
        [string]$Forward,
        $KeepCopy,
        [bool]$Disable
    )


    try {
        if (!$Username) { $Username = $UserID }
        if ($PSCmdlet.ShouldProcess($Username, 'Set forwarding')) {
            if ($Disable -eq $true) {
                Write-Output "Disabling forwarding for $Username"
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; ForwardingSMTPAddress = $null; ForwardingAddress = $null ; DeliverToMailboxAndForward = $false } -Anchor $Username
                $Message = "Successfully disabled forwarding for $Username"
            } elseif ($Forward) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; ForwardingSMTPAddress = $null; ForwardingAddress = $Forward ; DeliverToMailboxAndForward = $KeepCopy } -Anchor $Username
                $Message = "Successfully set forwarding for $Username to Internal Address $Forward with keeping a copy set to $KeepCopy"
            } elseif ($forwardingSMTPAddress) {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; ForwardingSMTPAddress = $ForwardingSMTPAddress; ForwardingAddress = $null ; DeliverToMailboxAndForward = $KeepCopy } -Anchor $Username
                $Message = "Successfully set forwarding for $Username to External Address $ForwardingSMTPAddress with keeping a copy set to $KeepCopy"
            }
        }
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set forwarding for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
