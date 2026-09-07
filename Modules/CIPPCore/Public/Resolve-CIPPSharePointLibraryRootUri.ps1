function Resolve-CIPPSharePointLibraryRootUri {
    <#
    .SYNOPSIS
        Resolves a document library list GUID to its absolute root folder URI via SPO REST.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$ListId,

        [string]$SiteUrl,
        [string]$SiteId
    )

    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        if ([string]::IsNullOrWhiteSpace($SiteId)) {
            throw 'SiteUrl or SiteId is required.'
        }
        $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId`?`$select=webUrl" -tenantid $TenantFilter -asapp $true
        if ([string]::IsNullOrWhiteSpace($SiteMeta.webUrl)) {
            throw "Could not resolve webUrl for site id $SiteId."
        }
        $SiteUrl = $SiteMeta.webUrl
    }

    $SiteUrl = $SiteUrl.TrimEnd('/')
    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
    $BaseUri = "$SiteUrl/_api"
    $SafeListId = $ListId -replace "'", "''"

    $List = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$SafeListId')?`$select=RootFolder/ServerRelativeUrl&`$expand=RootFolder" `
        -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true

    $ServerRelativeUrl = $List.RootFolder.ServerRelativeUrl
    if ([string]::IsNullOrWhiteSpace($ServerRelativeUrl)) {
        throw 'Could not resolve library root folder ServerRelativeUrl.'
    }

    $Origin = ([System.Uri]$SiteUrl).GetLeftPart([System.UriPartial]::Authority)
    $AbsoluteUri = "$Origin$ServerRelativeUrl"

    [PSCustomObject]@{
        SiteUrl           = $SiteUrl
        LibraryRootUri    = $AbsoluteUri
        ServerRelativeUrl = $ServerRelativeUrl
    }
}
