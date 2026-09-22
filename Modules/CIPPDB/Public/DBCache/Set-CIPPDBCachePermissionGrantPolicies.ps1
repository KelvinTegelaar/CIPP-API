function Set-CIPPDBCachePermissionGrantPolicies {
    <#
    .SYNOPSIS
        Caches permission grant policies for a tenant

    .PARAMETER TenantFilter
        The tenant to cache permission grant policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching permission grant policies' -sev Debug

        # includes/excludes are auto-expanded on GET; $expand is rejected by Graph
        $PermissionGrantPolicies = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/permissionGrantPolicies' -tenantid $TenantFilter)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PermissionGrantPolicies' -Data @($PermissionGrantPolicies) -AddCount
        $PermissionGrantPolicies = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached permission grant policies successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache permission grant policies: $($_.Exception.Message)" -sev Error
    }
}
