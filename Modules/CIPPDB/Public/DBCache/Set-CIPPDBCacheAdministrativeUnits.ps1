function Set-CIPPDBCacheAdministrativeUnits {
    <#
    .SYNOPSIS
        Caches a tenant's administrative units (id and name)

    .DESCRIPTION
        Lets cached views show 'AU: <name>' for role assignments scoped to an administrative unit
        instead of the raw /administrativeUnits/<id> scope.

    .PARAMETER TenantFilter
        The tenant to cache administrative units for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching administrative units' -sev Debug
        $Units = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/directory/administrativeUnits?$select=id,displayName,description,membershipType,visibility&$top=999' -tenantid $TenantFilter
        # Most tenants have none; -ClearOnEmpty clears units deleted since the last run.
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'AdministrativeUnits' -Data @($Units) -AddCount -ClearOnEmpty
        $Units = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached administrative units successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache administrative units: $($_.Exception.Message)" -sev Error
    }
}
