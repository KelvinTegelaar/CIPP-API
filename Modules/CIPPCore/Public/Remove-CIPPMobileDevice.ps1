function Remove-CIPPMobileDevice {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $username,
        $APIName = 'Remove Mobile',
        $ExecutingUser
    )

    try {
        $devices = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Get-MobileDevice' -Anchor $username -cmdParams @{mailbox = $username } | ForEach-Object {
            try {
                New-ExoRequest -tenantid $tenantFilter -cmdlet 'Remove-MobileDevice' -Anchor $username -cmdParams @{Identity = $_.Identity }
                "Removed device: $($_.FriendlyName)"
            } catch {
                "Could not remove device: $($_.FriendlyName)"
            }
        }
        if (!$Devices) { $Devices = 'No mobile devices have been removed as we could not find any' }
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Deleted mobile devices for $($username)" -Sev 'Info' -tenant $tenantFilter
        return $devices
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not delete mobile devices for $($username): $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $tenantFilter -LogData $ErrorMessage
        return "Could not delete mobile devices for $($username). Error: $($ErrorMessage.NormalizedError)"
    }
}
