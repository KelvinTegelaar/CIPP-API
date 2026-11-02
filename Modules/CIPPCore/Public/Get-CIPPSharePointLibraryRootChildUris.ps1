function Get-CIPPSharePointLibraryRootChildUris {
    <#
    .SYNOPSIS
        Enumerates eligible immediate children of a document library root for CreateCopyJobs.
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

    if ([string]::IsNullOrWhiteSpace($SiteId)) {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
            throw 'SiteUrl or SiteId is required.'
        }
        $ParsedUrl = [System.Uri]$SiteUrl
        $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
            $ParsedUrl.Host
        } else {
            "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
        }
        $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment`?`$select=id" -tenantid $TenantFilter -asapp $true
        $SiteId = $SiteMeta.id
    }

    $Uris = [System.Collections.Generic.List[string]]::new()
    $GraphUri = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/drive/root/children?`$select=name,webUrl,folder,file&`$top=999"

    try {
        $Children = @(New-GraphGetRequest -uri $GraphUri -tenantid $TenantFilter -asapp $true)
        foreach ($Child in $Children) {
            $Name = [string]$Child.name
            if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq 'Forms' -or $Name.StartsWith('_') -or $Name -match '\.(aspx|dotx)$') {
                continue
            }
            if ([string]::IsNullOrWhiteSpace($Child.webUrl)) { continue }
            if (-not ($Child.folder -or $Child.file)) { continue }
            $Uris.Add([string]$Child.webUrl)
        }
    } catch {
        $RootInfo = Resolve-CIPPSharePointLibraryRootUri -TenantFilter $TenantFilter -ListId $ListId -SiteUrl $SiteUrl -SiteId $SiteId
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($RootInfo.SiteUrl)/_api"
        $SafeListId = $ListId -replace "'", "''"
        $EscapedDir = $RootInfo.ServerRelativeUrl -replace "'", "''"
        $NextLink = "$BaseUri/web/lists(guid'$SafeListId')/items?`$filter=FileDirRef eq '$EscapedDir'&`$select=FileRef,FileLeafRef,FSObjType&`$top=5000"

        do {
            $Page = New-GraphGetRequest -uri $NextLink -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination
            $Items = @($Page.value)
            if ($Items.Count -eq 0 -and $Page.FileRef) { $Items = @($Page) }

            foreach ($Item in $Items) {
                $Leaf = [string]$Item.FileLeafRef
                if ([string]::IsNullOrWhiteSpace($Leaf) -or $Leaf -eq 'Forms' -or $Leaf.StartsWith('_') -or $Leaf -match '\.(aspx|dotx)$') {
                    continue
                }
                $FileRef = $Item.FileRef
                if ([string]::IsNullOrWhiteSpace($FileRef)) { continue }
                $Origin = ([System.Uri]$RootInfo.SiteUrl).GetLeftPart([System.UriPartial]::Authority)
                $Uris.Add("$Origin$FileRef")
            }

            $NextLink = $Page.'@odata.nextLink'
        } while (-not [string]::IsNullOrWhiteSpace($NextLink))
    }

    [PSCustomObject]@{
        ChildUris         = @($Uris)
        EligibleRootCount = $Uris.Count
    }
}
