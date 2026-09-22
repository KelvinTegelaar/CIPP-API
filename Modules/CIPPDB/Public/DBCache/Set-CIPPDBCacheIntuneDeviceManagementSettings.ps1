function Set-CIPPDBCacheIntuneDeviceManagementSettings {
    <#
    .SYNOPSIS
        Caches tenant-wide Intune device management settings

    .DESCRIPTION
        Caches the deviceManagement/settings singleton (secureByDefault,
        deviceComplianceCheckinThresholdDays and sibling properties) used by the
        IntuneComplianceSettings standard.

    .PARAMETER TenantFilter
        The tenant to cache Intune device management settings for

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
        $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneDeviceManagementSettingsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Intune device management settings cache' -sev Debug
            # A license skip is still a completed collection: record the authoritative empty set
            # so collect-on-miss does not re-run this collector forever on unlicensed tenants.
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceManagementSettings' -Data @() -AddCount -ClearOnEmpty
            return
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Intune device management settings' -sev Debug

        $DeviceManagementSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/settings' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceManagementSettings' -Data @($DeviceManagementSettings) -AddCount
        $DeviceManagementSettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Intune device management settings successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Intune device management settings: $($_.Exception.Message)" -sev Error
    }
}
