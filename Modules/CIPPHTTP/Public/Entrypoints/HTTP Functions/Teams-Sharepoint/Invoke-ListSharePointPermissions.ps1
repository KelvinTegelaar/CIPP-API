function Invoke-ListSharePointPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Compiles the SharePoint permissions report for a tenant from CACHED data in the CIPP
        reporting database (SharePointPermissions). No live enumeration is performed - refresh the
        data by syncing that cache (ExecCIPPDBCache). Returns the scan summary, the oversharing
        signals worth acting on, chart datasets and the individual permission assignments.

        Signals reported:
        - Broad claims: grants to Everyone, Everyone except external users, or All Users. A library
          carrying one of these is reachable by the whole tenant regardless of who was meant to
          have it, which is the classic oversharing footgun.
        - External grants: permissions held by guest or external identities.
        - Direct Full Control: Full Control held by something other than a SharePoint group, i.e.
          granted to a user or directory group rather than through the site's Owners group.
        - Unique permission libraries: libraries that no longer inherit from their site, so site
          level permission changes no longer reach them.

        Limited Access assignments (isSystemManaged) are excluded from every signal - SharePoint
        creates them itself so a user can traverse to an item, and they grant nothing on their own.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Body = Get-CIPPSharePointPermissionsReport -TenantFilter $TenantFilter

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
