function Set-CIPPDBCacheServiceHealthIssues {
    <#
    .SYNOPSIS
        Caches Microsoft 365 service health incidents and advisories for a tenant

    .PARAMETER TenantFilter
        The tenant to cache service health issues for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching service health issues' -sev Debug
        $Issues = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/issues' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServiceHealthIssues' -Data @($Issues) -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached service health issues successfully' -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache service health issues: $($_.Exception.Message)" -sev Error
        throw
    }
}
