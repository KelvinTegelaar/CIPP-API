function Set-CIPPDBCacheServiceHealthOverviews {
    <#
    .SYNOPSIS
        Caches the Microsoft 365 service health status per workload for a tenant

    .PARAMETER TenantFilter
        The tenant to cache service health for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service health overviews' -sev Debug
        $Overviews = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/healthOverviews' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServiceHealthOverviews' -Data @($Overviews) -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached service health overviews successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache service health overviews: $($_.Exception.Message)" -sev Error
        throw
    }
}
