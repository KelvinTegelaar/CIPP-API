function Invoke-AddSite {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers



    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $SharePointObj = $Request.Body

    try {
        $Result = New-CIPPSharepointSite -Headers $Headers -SiteName $SharePointObj.siteName -SiteDescription $SharePointObj.siteDescription -SiteOwner $SharePointObj.siteOwner.value -TemplateName $SharePointObj.templateName.value -SiteDesign $SharePointObj.siteDesign.value -SensitivityLabel $SharePointObj.sensitivityLabel -TenantFilter $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = $_.Exception.Message
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
