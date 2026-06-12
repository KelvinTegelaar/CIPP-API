function Get-CIPPStatsMobileEnrollment {
    [CmdletBinding()]
    param()

    try {
        $MobileEnrollment = 0
        $ManagedDeviceRows = Get-CIPPDbItem -TenantFilter allTenants -Type 'ManagedDevices'
        foreach ($ManagedDeviceRow in $ManagedDeviceRows) {
            if (-not $ManagedDeviceRow.Data) { continue }

            try {
                $ManagedDevice = $ManagedDeviceRow.Data | ConvertFrom-Json -Depth 20 -ErrorAction Stop
            } catch {
                continue
            }

            $OperatingSystem = [string]$ManagedDevice.operatingSystem
            if ($OperatingSystem -match 'iOS|iPadOS|Android') {
                $MobileEnrollment++
            }
        }

        return $MobileEnrollment
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate MobileEnrollment: $($_.Exception.Message)" -sev Warning
        return 0
    }
}
