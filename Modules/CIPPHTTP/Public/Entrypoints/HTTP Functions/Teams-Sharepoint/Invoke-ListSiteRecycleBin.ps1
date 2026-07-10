function Invoke-ListSiteRecycleBin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.SiteRecycleBin.Read
    .DESCRIPTION
        Lists the contents of a SharePoint site's recycle bin (first and second stage) via the
        SharePoint REST API with certificate authentication.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl

    $ItemTypeNames = @{ 1 = 'File'; 2 = 'File Version'; 3 = 'List Item'; 4 = 'List'; 5 = 'Folder'; 6 = 'Folder'; 7 = 'Attachment'; 8 = 'List Item Version'; 10 = 'Web' }
    $ItemStateNames = @{ 1 = 'First Stage'; 2 = 'Second Stage' }

    try {
        if (-not $SiteUrl) { throw 'SiteUrl is required.' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        $Items = New-GraphGetRequest -uri "$BaseUri/site/RecycleBin?`$top=500&`$orderby=DeletedDate desc" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true

        $Body = @($Items | ForEach-Object {
                [PSCustomObject]@{
                    Id            = $_.Id
                    Title         = $_.Title
                    LeafName      = $_.LeafName
                    DirName       = $_.DirName
                    ItemType      = $ItemTypeNames[[int]$_.ItemType] ?? $_.ItemType
                    ItemState     = $ItemStateNames[[int]$_.ItemState] ?? $_.ItemState
                    Size          = $_.Size
                    DeletedByName = $_.DeletedByName
                    DeletedDate   = $_.DeletedDate
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list the recycle bin for $($SiteUrl): $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}
