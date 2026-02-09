function Set-CIPPDBCacheManagedDevices {
    <#
    .SYNOPSIS
        Caches all Intune managed devices for a tenant

    .PARAMETER TenantFilter
        The tenant to cache managed devices for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching managed devices' -sev Debug
        $ManagedDevices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$top=999&$select=id,deviceName,operatingSystem,osVersion,complianceState,managedDeviceOwnerType,enrolledDateTime,lastSyncDateTime' -tenantid $TenantFilter
        if (!$ManagedDevices) { $ManagedDevices = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDevices' -Data $ManagedDevices
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDevices' -Data $ManagedDevices -Count
        $ManagedDevices = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached managed devices successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed devices: $($_.Exception.Message)" -sev Error
    }
}
