function Set-CIPPMailboxArchive {
    [CmdletBinding()]
    param (
        $Headers,
        $userid,
        $username,
        $APIName = 'Mailbox Archive',
        $TenantFilter,
        [bool]$ArchiveEnabled
    )

    $User = $Request.Headers

    Try {
        if (!$username) { $username = $userid }
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Enable-Mailbox' -cmdParams @{Identity = $userid; Archive = $ArchiveEnabled }
        "Successfully set archive for $username to $ArchiveEnabled"
        Write-LogMessage -Headers $User -API $APINAME -tenant $($tenantfilter) -message "Successfully set archive for $username to $ArchiveEnabled" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $User -API $APINAME -tenant $($tenantfilter) -message "Failed to set archive for $username. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        "Failed. $($ErrorMessage.NormalizedError)"
    }
}
