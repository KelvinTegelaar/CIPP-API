function Set-CIPPDBCacheServicePrincipals {
    <#
    .SYNOPSIS
        Caches all service principals for a tenant

    .PARAMETER TenantFilter
        The tenant to cache service principals for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service principals' -sev Debug

        New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipals' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached service principals successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache service principals: $($_.Exception.Message)" -sev Error
    }
}
