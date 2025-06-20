using namespace System.Net

Function Invoke-AddSiteBulk {
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
            $SharePointSite = New-CIPPSharepointSite -Headers $Headers -SiteName $sharePointObj.siteName -SiteDescription $sharePointObj.siteDescription -SiteOwner $sharePointObj.siteOwner -TemplateName $sharePointObj.templateName -SiteDesign $sharePointObj.siteDesign -SensitivityLabel $sharePointObj.sensitivityLabel -TenantFilter $Request.body.tenantFilter
            $Results.Add($SharePointSite)
        } catch {
            $Results.Add("Failed to create $($sharePointObj.siteName) Error message: $($_.Exception.Message)")
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{'Results' = $Results }
        })

}
