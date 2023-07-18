function Set-CIPPMobileDevice(
    [string]$ExecutingUser,
    [string]$Quarantine,
    [string]$UserId,
    [string]$DeviceId,
    [string]$TenantFilter,
    [string]$Delete,
    [string]$Guid,
    [string]$APIName = "Mobile Device"
) {
   
    try {
        if ($Quarantine -eq "false") {
            New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-CASMailbox" -cmdParams @{Identity = $UserId; ActiveSyncAllowedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; add = $DeviceId } }
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Allow Active Sync Device for $UserId" -Sev "Info"
            return "Allowed Active Sync Device for $UserId"
        }
        elseif ($Quarantine -eq "true") {
            New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-CASMailbox" -cmdParams @{Identity = $UserId; ActiveSyncBlockedDeviceIDs = @{'@odata.type' = '#Exchange.GenericHashTable'; add = $DeviceId } }
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Blocked Active Sync Device for $UserId" -Sev "Info"
            return "Blocked Active Sync Device for $UserId"
        }
    }
    catch {
        if ($Quarantine -eq 'false') {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to Allow Active Sync Device for $($UserId): $($_.Exception.Message)" -Sev "Error"
            return "Failed to Allow Active Sync Device for $($UserId): $($_.Exception.Message)"
        } 
        elseif ($Quarantine -eq 'true') {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to Block Active Sync Device for $($UserId): $($_.Exception.Message)" -Sev "Error"
            return "Failed to Block Active Sync Device for $($UserId): $($_.Exception.Message)"
        }
    }

    try {
        if ($Delete -eq 'true') {
            New-ExoRequest -tenant $TenantFilter -cmdlet "Remove-MobileDevice" -cmdParams @{Identity = $Guid; Confirm = $false } -UseSystemMailbox $true 
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Deleted Active Sync Device for $UserId" -Sev "Info"
            return "Deleted Active Sync Device for $UserId"
        }
    }
    catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Failed to delete Mobile Device $($Guid): $($_.Exception.Message)" -Sev "Error"
        return "Failed to delete Mobile Device $($Guid): $($_.Exception.Message)"
    }
}
