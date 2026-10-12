Function Invoke-AddSiteBulk {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers



    $Results = [System.Collections.Generic.List[System.Object]]::new()
    $Failed = 0

    foreach ($sharePointObj in $Request.Body.bulkSites) {
        try {
            $SiteParams = @{
                Headers          = $Headers
                SiteName         = $sharePointObj.siteName
                SiteDescription  = $sharePointObj.siteDescription
                SiteOwner        = $sharePointObj.siteOwner
                TemplateName     = $sharePointObj.templateName
                SensitivityLabel = $sharePointObj.sensitivityLabel
                IsPublic         = ([string]$sharePointObj.isPublic -in @('true', '1'))
                TenantFilter     = $Request.body.tenantFilter
            }
            # Optional. Only applies to the Team and Communication templates; leave blank for TeamGroup.
            if ($sharePointObj.siteDesign) { $SiteParams.SiteDesign = $sharePointObj.siteDesign }
            $SharePointSite = New-CIPPSharepointSite @SiteParams
            $Results.Add($SharePointSite)
        } catch {
            $Failed++
            $Results.Add("Failed to create $($sharePointObj.siteName) Error message: $($_.Exception.Message)")
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total @($Request.Body.bulkSites).Count -Failed $Failed
            Body       = @{'Results' = $Results }
        })

}
