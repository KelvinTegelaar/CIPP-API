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
    # Items to return in this call; Metadata.nextLink is set when the bin holds more.
    $MaxItems = $Request.Query.MaxItems -as [int]
    if ($MaxItems -lt 1) { $MaxItems = 5000 }
    # Offset to resume from, taken from a previous call's Metadata.nextLink.
    $Start = [Math]::Max(0, [int]($Request.Query.nextLink -as [int]))

    $ItemTypeNames = @{ 1 = 'File'; 2 = 'File Version'; 3 = 'List Item'; 4 = 'List'; 5 = 'Folder'; 6 = 'Folder'; 7 = 'Attachment'; 8 = 'List Item Version'; 10 = 'Web' }
    $ItemStateNames = @{ 1 = 'First Stage'; 2 = 'Second Stage' }

    if (-not $SiteUrl) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ 'Results' = 'SiteUrl is required.' } })
    }

    try {
        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Scope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri

        # The recycle bin returns no next link, so page with $skip.
        $Items = [System.Collections.Generic.List[object]]::new()
        do {
            $Top = [Math]::Min(500, $MaxItems - $Items.Count)
            $Page = @((New-GraphGetRequest -uri "$BaseUri/site/RecycleBin?`$top=$Top&`$skip=$($Start + $Items.Count)&`$orderby=DeletedDate desc" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction).value)
            $Items.AddRange($Page)
        } while ($Page.Count -eq $Top -and $Items.Count -lt $MaxItems)
        $NextLink = if ($Items.Count -eq $MaxItems) { [string]($Start + $MaxItems) }

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
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body; 'Metadata' = @{ nextLink = $NextLink } }
        })
}
