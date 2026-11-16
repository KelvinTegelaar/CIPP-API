function Set-CIPPDBCacheExoActiveSyncOrganizationSettings {
    <#
    .SYNOPSIS
        Caches the tenant's Exchange ActiveSync organization settings (default device access level)

    .PARAMETER TenantFilter
        The tenant to cache the settings for

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
        $Settings = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ActiveSyncOrganizationSettings'
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoActiveSyncOrganizationSettings' -Data @($Settings | Where-Object { $_ }) -AddCount -ClearOnEmpty
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache ActiveSync organization settings: $($_.Exception.Message)" -sev Error
    }
}
