function Set-CIPPDBCacheDefaultAppManagementPolicy {
    <#
    .SYNOPSIS
        Caches default app management policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache policy for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching default app management policy' -sev Debug
        $AppMgmtPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/defaultAppManagementPolicy' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefaultAppManagementPolicy' -Data @($AppMgmtPolicy)
        $AppMgmtPolicy = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached default app management policy successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache default app management policy: $($_.Exception.Message)" -sev Error
    }
}
