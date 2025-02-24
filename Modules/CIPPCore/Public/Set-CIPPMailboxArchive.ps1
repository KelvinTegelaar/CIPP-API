function Set-CIPPMailboxArchive {
    [CmdletBinding()]
    param (
        $Headers,
        $UserID,
        $Username,
        $APIName = 'Mailbox Archive',
        $TenantFilter,
        [bool]$ArchiveEnabled
    )

    try {
        if (!$Username) { $Username = $UserID }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Enable-Mailbox' -cmdParams @{Identity = $UserID; Archive = $ArchiveEnabled }
        $Message = "Successfully set archive for $Username to $ArchiveEnabled"
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set archive for $Username. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        return $Message
    }
}
