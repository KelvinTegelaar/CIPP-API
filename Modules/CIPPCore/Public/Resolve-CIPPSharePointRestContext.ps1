function Resolve-CIPPSharePointRestContext {
    <#
    .SYNOPSIS
    Resolve the SharePoint REST context for a site-scoped API call

    .DESCRIPTION
    Builds the certificate-authenticated SharePoint REST plumbing shared by site-scoped
    endpoints: the token scope, odata headers, normalized site URL and the /_api base URI.
    Pass -SharePointInfo when resolving several sites in one operation to avoid repeated
    admin-link lookups.

    .PARAMETER TenantFilter
    The tenant the site belongs to

    .PARAMETER SiteUrl
    The full URL of the site

    .PARAMETER SharePointInfo
    Optional output from Get-SharePointAdminLink to reuse across multiple sites
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [object]$SharePointInfo
    )

    if (-not $SharePointInfo) {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    }

    $NormalizedSiteUrl = $SiteUrl.TrimEnd('/')
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $Headers = @{ Accept = 'application/json;odata=nometadata' }
    $BaseUri = "$NormalizedSiteUrl/_api"

    return [PSCustomObject]@{
        SharePointInfo = $SharePointInfo
        SiteUrl        = $NormalizedSiteUrl
        Scope          = $Scope
        Headers        = $Headers
        BaseUri        = $BaseUri
        WebUri         = "$BaseUri/web"
    }
}
