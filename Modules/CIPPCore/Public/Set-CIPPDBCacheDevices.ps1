function Set-CIPPDBCacheDevices {
    <#
    .SYNOPSIS
        Caches all Azure AD devices for a tenant

    .PARAMETER TenantFilter
        The tenant to cache devices for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Azure AD devices' -sev Debug

        $Devices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/devices?$top=999&$select=id,displayName,operatingSystem,operatingSystemVersion,trustType,accountEnabled,approximateLastSignInDateTime' -tenantid $TenantFilter
        if (!$Devices) { $Devices = @() }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Devices' -Data $Devices
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Devices' -Data $Devices -Count
        $Devices = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Azure AD devices successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Azure AD devices: $($_.Exception.Message)" -sev Error
    }
}
