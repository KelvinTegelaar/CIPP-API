function Remove-CIPPMobileDevice {
    [CmdletBinding()]
    param(
        $UserId,
        $TenantFilter,
        $Username,
        $APIName = 'Remove Mobile',
        $Headers
    )

    try {
        $RemovedDevices = [System.Collections.Generic.List[string]]::new()
        $ErrorDevices = [System.Collections.Generic.List[string]]::new()
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MobileDevice' -Anchor $Username -cmdParams @{mailbox = $Username } | ForEach-Object {
            try {
                $MobileDevice = $_
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-MobileDevice' -Anchor $Username -cmdParams @{Identity = $MobileDevice.Identity }
                $RemovedDevices.Add("$($MobileDevice.FriendlyName)")
            } catch {
                $ErrorDevices.Add("$($MobileDevice.FriendlyName)")
            }
        }
        if ($ErrorDevices.Count -eq 0) {
            $Message = "Successfully removed $($RemovedDevices.Count) mobile devices for $($Username): $($RemovedDevices -join '; ')"
        } else {
            $Message = "Failed to remove all mobile devices for $($Username). Successfully removed $($RemovedDevices.Count) mobile devices: $($RemovedDevices -join '; '). Failed to remove $($ErrorDevices.Count) mobile devices: $($ErrorDevices -join '; ')"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter
        }
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to remove mobile devices for $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}

