function Invoke-ListDeletedSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists deleted SharePoint sites still restorable from the tenant recycle bin, via the
        SharePoint admin CSOM API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    # CSOM verbose JSON dates arrive as '/Date(year,month,day,h,m,s,ms)/' with a 0-based month.
    function ConvertFrom-CsomDate($Value) {
        if ("$Value" -match '/Date\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)/') {
            return ([datetime]::new([int]$Matches[1], ([int]$Matches[2] + 1), [int]$Matches[3], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6], [System.DateTimeKind]::Utc)).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        return $Value
    }

    try {
        $DeletedSites = Get-CIPPSPODeletedSites -TenantFilter $TenantFilter
        $Body = @($DeletedSites | ForEach-Object {
                [PSCustomObject]@{
                    # Deleted-site CSOM entries carry no Title; derive a display name from the URL.
                    Name                = ([uri]$_.Url).Segments[-1].TrimEnd('/')
                    Url                 = $_.Url
                    SiteId              = $_.SiteId
                    Status              = $_.Status
                    DeletionTime        = ConvertFrom-CsomDate $_.DeletionTime
                    DaysRemaining       = $_.DaysRemaining
                    StorageMaximumLevel = $_.StorageMaximumLevel
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list deleted sites: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}
