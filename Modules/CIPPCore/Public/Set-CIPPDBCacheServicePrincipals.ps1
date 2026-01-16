function Set-CIPPDBCacheServicePrincipals {
    <#
    .SYNOPSIS
        Caches all service principals for a tenant

    .PARAMETER TenantFilter
        The tenant to cache service principals for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service principals' -sev Info

        $ServicePrincipals = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Data $ServicePrincipals
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Data $ServicePrincipals -Count
        $ServicePrincipals = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached service principals successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache service principals: $($_.Exception.Message)" -sev Error
    }
}
