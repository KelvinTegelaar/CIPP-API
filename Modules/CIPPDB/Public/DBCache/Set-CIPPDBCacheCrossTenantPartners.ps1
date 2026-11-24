function Set-CIPPDBCacheCrossTenantPartners {
    <#
    .SYNOPSIS
        Caches a tenant's cross-tenant access partner organisations

    .PARAMETER TenantFilter
        The tenant to cache partner organisations for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching cross-tenant partner organisations' -sev Debug
        $Partners = @(Get-CIPPCrossTenantPartner -TenantFilter $TenantFilter)
        # Most tenants have none; -ClearOnEmpty clears partners removed since the last run.
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CrossTenantPartners' -Data $Partners -AddCount -ClearOnEmpty
        $Partners = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached cross-tenant partner organisations successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache cross-tenant partner organisations: $($_.Exception.Message)" -sev Error
    }
}
