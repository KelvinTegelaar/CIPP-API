function Push-DBCacheSPOSitesBatch {
    <#
    .SYNOPSIS
        Reads the per-site settings for one batch of SharePoint site URLs.

    .DESCRIPTION
        Returns the batch's input URLs and one row per site that answered. A site whose read failed is
        left out, so Push-StoreSPOSites can carry its previous row over instead of caching defaults.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Urls = @($Item.Urls)
    $Fields = @('SiteId', 'Title', 'Template', 'ShowPeoplePickerSuggestionsForGuestUsers')
    $Sites = foreach ($Result in @(Get-CIPPSPOSiteBulk -TenantFilter $Item.TenantFilter -SiteUrls $Urls -MaxConcurrency 3 -BatchSize 8 -Properties $Fields -UseCertificate)) {
        if (-not ($Result.Success -and $Result.Site)) { continue }
        $Site = $Result.Site
        [PSCustomObject]@{
            id                                       = "$($Site.SiteId)"
            Url                                      = "$($Result.SiteUrl)"
            Title                                    = $Site.Title
            Template                                 = $Site.Template
            ShowPeoplePickerSuggestionsForGuestUsers = $Site.ShowPeoplePickerSuggestionsForGuestUsers
        }
    }
    @{ Urls = $Urls; Sites = @($Sites) }
}
