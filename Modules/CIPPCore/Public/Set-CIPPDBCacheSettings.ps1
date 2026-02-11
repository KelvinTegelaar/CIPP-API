function Set-CIPPDBCacheSettings {
    <#
    .SYNOPSIS
        Caches directory settings for a tenant

    .PARAMETER TenantFilter
        The tenant to cache settings for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching directory settings' -sev Debug

        $Settings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/settings?$top=999' -tenantid $TenantFilter
        if(!$Settings){ $Settings = @()}
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Settings' -Data $Settings
        $Settings = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached directory settings successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache directory settings: $($_.Exception.Message)" -sev Error
    }
}
