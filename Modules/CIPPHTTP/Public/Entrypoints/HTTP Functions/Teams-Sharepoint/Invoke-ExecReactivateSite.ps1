function Invoke-ExecReactivateSite {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .SYNOPSIS
        Reactivate an archived SharePoint or OneDrive site.
    .DESCRIPTION
        Reactivates (unarchives) a Microsoft 365 Archive site through the Graph beta
        site: unarchive endpoint (POST /beta/sites/{site-id}/unarchive). Primarily used to
        reactivate archived OneDrive accounts before granting permissions to them.
        Reactivation is asynchronous (can take up to 24 hours) and, for fully-archived
        accounts, may incur Microsoft 365 Archive charges and require Unlicensed OneDrive
        billing to be enabled on the tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Tenant the archived site belongs to.
    $TenantFilter = $Request.Body.tenantFilter
    # Full web URL of the archived site / OneDrive (the row's webUrl).
    $SiteUrl = $Request.Body.SiteUrl
    # Site-collection GUID (the row's siteId / sharepointIds.siteId). Used to build the Graph
    # composite site id without touching the locked, archived site.
    $SiteId = $Request.Body.SiteId
    # Web GUID (the row's webId / sharepointIds.webId).
    $WebId = $Request.Body.WebId

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }

        $SiteHost = ([System.Uri]$SiteUrl).Host
        if ([string]::IsNullOrWhiteSpace($SiteHost)) { throw "SiteUrl '$SiteUrl' is not a valid URL." }

        # Prefer building the Graph composite id ({host},{siteCollectionId},{webId}) from the
        # ids the site listing already carries: an archived site is locked, so avoid any lookup
        # against it. Fall back to resolving the id by path only when those ids are absent.
        if (-not [string]::IsNullOrWhiteSpace($SiteId) -and -not [string]::IsNullOrWhiteSpace($WebId)) {
            $GraphSiteId = '{0},{1},{2}' -f $SiteHost, $SiteId, $WebId
        } else {
            $RelativePath = ([System.Uri]$SiteUrl).AbsolutePath.TrimStart('/')
            $Resolved = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$($SiteHost):/$($RelativePath)?`$select=id" -tenantid $TenantFilter -AsApp $true
            $GraphSiteId = $Resolved.id
        }

        if ([string]::IsNullOrWhiteSpace($GraphSiteId)) {
            throw "Could not determine the site id for $SiteUrl."
        }

        # site: unarchive is beta-only. App-only auth is used deliberately: the SAM app holds the
        # Sites.FullControl.All application role, which this endpoint accepts, so no per-admin
        # SharePoint-admin role is required. A 202 with an empty body (Invoke-CIPPRestMethod
        # returns $null) is the success signal - no exception means reactivation was accepted.
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/sites/$GraphSiteId/unarchive" -tenantid $TenantFilter -AsApp $true -type POST -body ''

        $Results = "Reactivation started for $SiteUrl. It can take up to 24 hours to complete. If the account was fully archived, this may incur Microsoft 365 Archive charges and requires Unlicensed OneDrive billing to be enabled on the tenant."
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to reactivate $($SiteUrl): $($ErrorMessage.NormalizedError)"
        # A 423 (Locked) / "blocked" response is a known limitation of the beta unarchive endpoint
        # for archived sites, and a billing failure means Unlicensed OneDrive billing is off. In
        # both cases the reliable fallback is the SharePoint admin center.
        if ($ErrorMessage.NormalizedError -match '423|[Ll]ocked|blocked|billing') {
            $Results += ' Reactivation may need Unlicensed OneDrive billing enabled on the tenant, or the site cannot be reactivated via the API right now - reactivate it from the SharePoint admin center.'
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
