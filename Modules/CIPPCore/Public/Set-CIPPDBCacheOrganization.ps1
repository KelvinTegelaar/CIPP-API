function Set-CIPPDBCacheOrganization {
    <#
    .SYNOPSIS
        Caches organization information for a tenant

    .PARAMETER TenantFilter
        The tenant to cache organization data for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching organization data' -sev Info

        $Organization = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Organization' -Data $Organization
        $Organization = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached organization data successfully' -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache organization data: $($_.Exception.Message)" -sev Error
    }
}
