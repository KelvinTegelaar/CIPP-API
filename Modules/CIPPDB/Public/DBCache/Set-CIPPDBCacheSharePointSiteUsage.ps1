function Set-CIPPDBCacheSharePointSiteUsage {
    <#
    .SYNOPSIS
        Caches SharePoint site listing and site usage details for a tenant

    .DESCRIPTION
        Active sites + usage from SPO admin RenderAdminListData (same source as the site browser),
        Graph getAllSites for Graph ids / sharepointIds, Get-CIPPSPOSite for file-level archive
        metrics, and a Graph lists bulk pass for AutoMapUrl. Writes the same SharePointSiteListing
        and SharePointSiteUsage property shapes consumed by Get-CIPPSharePointSiteUsageReport.

    .PARAMETER TenantFilter
        The tenant to cache SharePoint site usage for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching SharePoint site listing and usage' -sev Debug

        $Built = Get-CIPPSharePointSiteUsageRows -TenantFilter $TenantFilter -IncludeArchive -LogApi 'CIPPDBCache'

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteListing' -Data @($Built.SiteListing) -AddCount
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSiteUsage' -Data @($Built.UsageRows) -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached SharePoint site listing and usage successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache SharePoint site usage: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
