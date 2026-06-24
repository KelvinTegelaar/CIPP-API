function Set-CIPPDBCacheDevices {
    <#
    .SYNOPSIS
        Caches all Entra ID devices for a tenant

    .PARAMETER TenantFilter
        The tenant to cache devices for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Entra ID devices' -sev Debug

        $Devices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/devices?$top=999&$select=id,displayName,operatingSystem,operatingSystemVersion,trustType,accountEnabled,approximateLastSignInDateTime' -tenantid $TenantFilter
        if (!$Devices) { $Devices = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Devices' -Data $Devices -AddCount
        $Devices = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Entra ID devices successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Entra ID devices: $($_.Exception.Message)" -sev Error
    }
}
