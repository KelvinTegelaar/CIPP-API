function Clear-CIPPMobileDevice {
    [CmdletBinding()]
    param(
        $UserId,
        $TenantFilter,
        $Username,
        $APIName = 'Wipe Mobile',
        $Headers
    )

    try {
        $WipedDevices = [System.Collections.Generic.List[string]]::new()
        $ErrorDevices = [System.Collections.Generic.List[string]]::new()
        # AccountOnly wipes the Exchange account data from the device, never the full device.
        # Requires EAS v16.1+; older clients fail the call rather than falling back to a device wipe.
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice' -Anchor $Username -cmdParams @{mailbox = $Username } | ForEach-Object {
            try {
                $MobileDevice = $_
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Clear-MobileDevice' -Anchor $Username -cmdParams @{Identity = $MobileDevice.Identity; AccountOnly = $true }
                $WipedDevices.Add("$($MobileDevice.FriendlyName)")
            } catch {
                $ErrorDevices.Add("$($MobileDevice.FriendlyName)")
            }
        }
        if ($ErrorDevices.Count -eq 0) {
            $Message = "Successfully issued an account-only wipe for $($WipedDevices.Count) mobile devices for $($Username): $($WipedDevices -join '; '). The wipe is performed when the device next connects to Exchange."
        } else {
            $Message = "Failed to wipe all mobile devices for $($Username). Successfully issued an account-only wipe for $($WipedDevices.Count) mobile devices: $($WipedDevices -join '; '). Failed to wipe $($ErrorDevices.Count) mobile devices: $($ErrorDevices -join '; ')"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter
        }
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to wipe mobile devices for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
