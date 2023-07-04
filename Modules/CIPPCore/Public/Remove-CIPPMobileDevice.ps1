function Remove-CIPPMobileDevice {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $username,
        $APIName = "Remove Mobile",
        $ExecutingUser
    )

    try {
        $devices = New-ExoRequest -tenantid $tenantFilter -cmdlet "Get-MobileDevice" -Anchor $username -cmdParams @{mailbox = $userid } | ForEach-Object {
            try {
                New-ExoRequest -tenantid $tenantFilter -cmdlet "Remove-MobileDevice" -Anchor $username -cmdParams @{Identity = $_.Identity }
                "Removed device: $($_.FriendlyName)"
            }
            catch {
                "Could not remove device: $($_.FriendlyName)"
                continue
            }
        }

        Write-LogMessage -user $ExecutingUser -API $APIName -message "Deleted mobile devices for $($username)" -Sev "Info" -tenant $tenantFilter
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not delete mobile devices for $($username): $($_.Exception.Message)" -Sev "Error" -tenant $tenantFilter
        return "Could not delete mobile devices for $($username). Error: $($_.Exception.Message)"
    }
}
