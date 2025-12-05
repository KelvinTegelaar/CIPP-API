function Set-CIPPMailboxArchive {
    [CmdletBinding()]
    param (
        $Headers,
        $UserID,
        $Username,
        $APIName = 'Mailbox Archive',
        $TenantFilter,
        [bool]$ArchiveEnabled,
        [switch]$AutoExpandingArchive
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Username)) { $Username = $UserID }
        $OperationType = if ($AutoExpandingArchive.IsPresent -eq $true) { 'auto-expanding archive' } else { 'archive' }
        if ($AutoExpandingArchive.IsPresent -eq $true) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Enable-Mailbox' -cmdParams @{Identity = $UserID; AutoExpandingArchive = $true }
            $Message = "Successfully enabled $OperationType for $Username"
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Enable-Mailbox' -cmdParams @{Identity = $UserID; Archive = $ArchiveEnabled }
            $Message = "Successfully set $OperationType for $Username to $ArchiveEnabled"
        }

        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set $OperationType for $Username. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
