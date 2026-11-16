function Set-CIPPDBCacheMobileDevices {
    <#
    .SYNOPSIS
        Caches Exchange mobile devices (ActiveSync and Outlook mobile) for a tenant

    .PARAMETER TenantFilter
        The tenant to cache mobile devices for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching mobile devices' -sev Debug
        $Devices = @(Get-CIPPMobileDevice -TenantFilter $TenantFilter)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MobileDevices' -Data $Devices -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Devices.Count) mobile devices" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache mobile devices: $($_.Exception.Message)" -sev Error
    }
}
