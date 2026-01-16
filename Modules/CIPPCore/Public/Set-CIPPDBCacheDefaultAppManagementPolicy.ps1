function Set-CIPPDBCacheDefaultAppManagementPolicy {
    <#
    .SYNOPSIS
        Caches default app management policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache policy for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching default app management policy' -sev Info
        $AppMgmtPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/defaultAppManagementPolicy' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'DefaultAppManagementPolicy' -Data @($AppMgmtPolicy)
        $AppMgmtPolicy = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached default app management policy successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache default app management policy: $($_.Exception.Message)" -sev Error
    }
}
