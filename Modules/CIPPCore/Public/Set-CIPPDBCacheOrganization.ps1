function Set-CIPPDBCacheOrganization {
    <#
    .SYNOPSIS
        Caches organization information for a tenant

    .PARAMETER TenantFilter
        The tenant to cache organization data for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching organization data' -sev Debug

        $Organization = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Organization' -Data $Organization
        $Organization = $null

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached organization data successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache organization data: $($_.Exception.Message)" -sev Error
    }
}
