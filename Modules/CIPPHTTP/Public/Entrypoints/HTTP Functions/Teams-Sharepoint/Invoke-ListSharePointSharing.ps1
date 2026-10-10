function Invoke-ListSharePointSharing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Compiles the SharePoint & OneDrive sharing report for a tenant from CACHED data in the
        CIPP reporting database (SharePointSharingLinks, SharePointSiteUsage, OneDriveUsage).
        No live Graph enumeration is performed - refresh the data by syncing those caches
        (ExecCIPPDBCache). Returns environment/file/storage summaries per workload, sharing link
        counts by classification, chart datasets and the individual sharing link rows.

        Also rolls up the sharing sprawl signals held in the same rows: anonymous links that allow
        editing, anonymous links with no expiry, folder-level external shares (one share exposes
        everything below it), and the busiest libraries and external recipients.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Body = Get-CIPPSharePointSharingReport -TenantFilter $TenantFilter

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
