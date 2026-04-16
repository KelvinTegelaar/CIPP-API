function Set-CIPPDBCacheDetectedApps {
    <#
    .SYNOPSIS
        Caches all detected apps for a tenant, including devices that have each app

    .PARAMETER TenantFilter
        The tenant to cache detected apps for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching detected apps' -sev Debug

        # Fetch all detected apps for the tenant
        $DetectedApps = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/detectedApps' -tenantid $TenantFilter
        if (!$DetectedApps) { $DetectedApps = @() }

        if (($DetectedApps | Measure-Object).Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No detected apps found' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data @()
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data @() -Count
            return
        }

        # Build bulk request for devices that have each detected app
        $DeviceRequests = $DetectedApps | ForEach-Object {
            if ($_.id) {
                [PSCustomObject]@{
                    id     = $_.id
                    method = 'GET'
                    url    = "deviceManagement/detectedApps('$($_.id)')/managedDevices"
                }
            }
        }

        if ($DeviceRequests) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching devices for $($DetectedApps.Count) detected apps" -sev Debug
            $DeviceResults = New-GraphBulkRequest -Requests @($DeviceRequests) -tenantid $TenantFilter

            # Add devices to each detected app object
            $DetectedAppsWithDevices = foreach ($App in $DetectedApps) {
                $Devices = Get-GraphBulkResultByID -Results $DeviceResults -ID $App.id -Value
                if ($Devices) {
                    $App | Add-Member -NotePropertyName 'managedDevices' -NotePropertyValue $Devices -Force
                } else {
                    $App | Add-Member -NotePropertyName 'managedDevices' -NotePropertyValue @() -Force
                }
                $App
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedAppsWithDevices
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedAppsWithDevices -Count
            $DetectedApps = $null
            $DetectedAppsWithDevices = $null
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedApps
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DetectedApps' -Data $DetectedApps -Count
            $DetectedApps = $null
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached detected apps with devices successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache detected apps: $($_.Exception.Message)" -sev Error
    }
}
