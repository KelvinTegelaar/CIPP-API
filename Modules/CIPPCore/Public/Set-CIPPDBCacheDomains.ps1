function Set-CIPPDBCacheDomains {
    <#
    .SYNOPSIS
        Caches domains for a tenant

    .PARAMETER TenantFilter
        The tenant to cache domains for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching domains' -sev Debug
        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Domains' -Data @($Domains)
        $Domains = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached domains successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache domains: $($_.Exception.Message)" -sev Error
    }
}
