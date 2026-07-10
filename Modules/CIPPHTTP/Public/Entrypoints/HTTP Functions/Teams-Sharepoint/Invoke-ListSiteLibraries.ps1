function Invoke-ListSiteLibraries {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists the visible document libraries of a SharePoint site via the Graph API. The site can
        be addressed by SiteId or by SiteUrl (hostname:path addressing). Returns the SharePoint
        list GUID as Id so the result can be used directly against the SharePoint REST API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SiteId = $Request.Query.SiteId ?? $Request.Body.SiteId
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl

    try {
        # Resolve the site addressing segment: prefer the Graph site id, else hostname:path from the URL.
        if (-not [string]::IsNullOrWhiteSpace($SiteId)) {
            $SiteSegment = $SiteId
        } elseif (-not [string]::IsNullOrWhiteSpace($SiteUrl)) {
            $ParsedUrl = [System.Uri]$SiteUrl
            $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
                $ParsedUrl.Host
            } else {
                "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
            }
        } else {
            throw 'SiteId or SiteUrl is required.'
        }

        $Lists = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteSegment/lists?`$select=id,displayName,name,webUrl,list" -tenantid $TenantFilter -asapp $true
        # documentLibrary covers regular libraries; webPageLibrary is the Site Pages library.
        $Results = @($Lists | Where-Object { $_.list.hidden -ne $true -and $_.list.template -in @('documentLibrary', 'webPageLibrary') } | ForEach-Object {
                [PSCustomObject]@{
                    Id       = $_.id
                    Title    = $_.displayName
                    Template = $_.list.template
                    WebUrl   = $_.webUrl
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list document libraries: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results }
        })
}
