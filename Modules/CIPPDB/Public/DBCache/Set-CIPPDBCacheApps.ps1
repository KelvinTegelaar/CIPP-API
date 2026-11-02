function Set-CIPPDBCacheApps {
    <#
    .SYNOPSIS
        Caches all application registrations for a tenant

    .PARAMETER TenantFilter
        The tenant to cache applications for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching applications' -sev Debug

        New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/applications?$top=999&expand=owners' -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Apps' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached applications successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache applications: $($_.Exception.Message)" -sev Error
    }
}
