function Set-CIPPMailboxType {
    [CmdletBinding()]
    param (
        $Headers,
        $UserID,
        $Username,
        $APIName = 'Mailbox Conversion',
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Shared', 'Regular', 'Room', 'Equipment')]$MailboxType
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Username)) { $Username = $UserID }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; Type = $MailboxType } -Anchor $Username
        $Message = "Successfully converted $Username to a $MailboxType mailbox"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to convert $Username to a $MailboxType mailbox. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
