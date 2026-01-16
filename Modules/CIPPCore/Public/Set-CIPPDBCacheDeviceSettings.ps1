function Set-CIPPDBCacheDeviceSettings {
    <#
    .SYNOPSIS
        Caches device settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache device settings for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching device settings' -sev Info

        $DeviceSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directory/deviceLocalCredentials' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DeviceSettings' -Data @($DeviceSettings)
        $DeviceSettings = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached device settings successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache device settings: $($_.Exception.Message)" -sev Error
    }
}
