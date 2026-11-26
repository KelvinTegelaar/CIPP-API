function Set-CIPPMobileDevice(
    [string]$Headers,
    [string]$Quarantine,
    [string]$UserId,
    [string]$DeviceId,
    [string]$TenantFilter,
    [string]$Delete,
    [string]$Guid,
    [string]$Wipe,
    [string]$CancelWipe,
    [string]$APIName = 'Mobile Device'
) {

    # Delete is evaluated first: the caller sends Quarantine 'false' alongside Delete 'true', so
    # testing Quarantine up front would allow the device and return before ever reaching the removal.
    try {
        if ($Delete -eq 'true') {
            New-ExoRequest -tenant $TenantFilter -cmdlet 'Remove-MobileDevice' -cmdParams @{Identity = $Guid; Confirm = $false } -UseSystemMailbox $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted Active Sync Device for $UserId" -Sev 'Info'
            return "Deleted Active Sync Device for $UserId"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to delete Mobile Device $($Guid): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to delete Mobile Device $($Guid): $($ErrorMessage.NormalizedError)"
    }

    try {
        if ($Wipe -eq 'true') {
            # AccountOnly removes the Exchange account data, never the whole device. Needs EAS 16.1+ or Outlook mobile.
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Clear-MobileDevice' -Anchor $UserId -cmdParams @{Identity = $Guid; AccountOnly = $true }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Issued an account-only wipe for a mobile device of $UserId" -Sev 'Info'
            return "Issued an account-only wipe for the mobile device of $UserId. The wipe is performed when the device next connects to Exchange."
        } elseif ($CancelWipe -eq 'true') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Clear-MobileDevice' -Anchor $UserId -cmdParams @{Identity = $Guid; AccountOnly = $true; Cancel = $true }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Cancelled the account-only wipe for a mobile device of $UserId" -Sev 'Info'
            return "Cancelled the pending account-only wipe for the mobile device of $UserId"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Action = if ($Wipe -eq 'true') { 'wipe' } else { 'cancel the wipe for' }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to $Action Mobile Device $($Guid): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        throw "Failed to $Action Mobile Device $($Guid): $($ErrorMessage.NormalizedError)"
    }

    try {
        if ($Quarantine -eq 'false') {
            # Each list change also takes the id off the opposite list, so allowing a device that was blocked unblocks it
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams @{Identity = $UserId; ActiveSyncAllowedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; add = $DeviceId }; ActiveSyncBlockedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; remove = $DeviceId } }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Allow Active Sync Device for $UserId" -Sev 'Info'
            return "Allowed Active Sync Device for $UserId"
        } elseif ($Quarantine -eq 'true') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams @{Identity = $UserId; ActiveSyncBlockedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; add = $DeviceId }; ActiveSyncAllowedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; remove = $DeviceId } }
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Blocked Active Sync Device for $UserId" -Sev 'Info'
            return "Blocked Active Sync Device for $UserId"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if ($Quarantine -eq 'false') {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to Allow Active Sync Device for $($UserId): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            throw "Failed to Allow Active Sync Device for $($UserId): $($ErrorMessage.NormalizedError)"
        } elseif ($Quarantine -eq 'true') {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to Block Active Sync Device for $($UserId): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            throw "Failed to Block Active Sync Device for $($UserId): $($ErrorMessage.NormalizedError)"
        }
    }
}
