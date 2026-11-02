function Invoke-ListSharePointSharing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Compiles the SharePoint & OneDrive sharing report for a tenant from CACHED data: the
        cached sharing links plus the SharePointSiteUsage and OneDriveUsage datasets. No live
        Graph enumeration is performed - refresh the data by syncing those caches
        (ExecCIPPDBCache). Returns environment/file/storage summaries per workload, sharing link
        counts by classification, chart datasets, the individual sharing link rows, and the state
        of any sharing links scan still running (when it started, its queue and its current phase).

        Also rolls up the sharing sprawl signals held in the same rows: anonymous links that allow
        editing, anonymous links with no expiry, folder-level external shares (one share exposes
        everything below it), and the busiest libraries and external recipients.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Only the running scan's progress, library by library - cheap enough to poll while a scan runs.
    $Body = if ([string]($Request.Query.ScanStatusOnly ?? $Request.Body.ScanStatusOnly) -eq 'true') {
        @{ scan = Get-CIPPSharingLinksScanStatus -TenantFilter $TenantFilter -Libraries }
    } else {
        Get-CIPPSharePointSharingReport -TenantFilter $TenantFilter
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
