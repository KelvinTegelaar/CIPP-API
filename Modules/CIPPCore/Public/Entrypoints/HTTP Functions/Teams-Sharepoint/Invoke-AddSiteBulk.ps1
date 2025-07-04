using namespace System.Net

function Invoke-AddSiteBulk {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $Results = [System.Collections.Generic.List[System.Object]]::new()

    foreach ($sharePointObj in $Request.Body.bulkSites) {
        try {
            $SharePointParams = @{
                Headers          = $Headers
                SiteName         = $sharePointObj.siteName
                SiteDescription  = $sharePointObj.siteDescription
                SiteOwner        = $sharePointObj.siteOwner
                TemplateName     = $sharePointObj.templateName
                SiteDesign       = $sharePointObj.siteDesign
                SensitivityLabel = $sharePointObj.sensitivityLabel
                TenantFilter     = $Request.body.tenantFilter
            }
            $SharePointSite = New-CIPPSharepointSite @SharePointParams
            $Results.Add($SharePointSite)
        } catch {
            $Results.Add("Failed to create $($sharePointObj.siteName) Error message: $($_.Exception.Message)")
        }
    }
    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
