function Set-CIPPDBCacheCrossTenantAccessPolicy {
    <#
    .SYNOPSIS
        Caches cross-tenant access policy for a tenant

    .PARAMETER TenantFilter
        The tenant to cache policy for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching cross-tenant access policy' -sev Info
        $CrossTenantPolicy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/crossTenantAccessPolicy/default' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CrossTenantAccessPolicy' -Data @($CrossTenantPolicy)
        $CrossTenantPolicy = $null
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached cross-tenant access policy successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache cross-tenant access policy: $($_.Exception.Message)" -sev Error
    }
}
