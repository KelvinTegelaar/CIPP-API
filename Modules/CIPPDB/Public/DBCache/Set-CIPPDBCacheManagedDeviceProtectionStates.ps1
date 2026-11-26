function Set-CIPPDBCacheManagedDeviceProtectionStates {
    <#
    .SYNOPSIS
        Caches the Microsoft Defender antivirus state of each Intune managed device for a tenant

    .PARAMETER TenantFilter
        The tenant to cache Defender antivirus state for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching managed device Defender state' -sev Debug
        New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$expand=windowsProtectionState&$select=id,deviceName,operatingSystem,osVersion,azureADDeviceId,windowsProtectionState' -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDeviceProtectionStates' -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached managed device Defender state successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed device Defender state: $($_.Exception.Message)" -sev Error
    }
}
