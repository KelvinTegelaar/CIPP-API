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
        $SiteParams = @{
            Headers          = $Headers
            SiteName         = $SharePointObj.siteName
            SiteDescription  = $SharePointObj.siteDescription
            SiteOwner        = $SharePointObj.siteOwner.value
            TemplateName     = $SharePointObj.templateName.value
            SensitivityLabel = $SharePointObj.sensitivityLabel
            IsPublic         = ($SharePointObj.isPublic -eq $true)
            TenantFilter     = $TenantFilter
        }
        # Optional. Only applies to the Team and Communication templates; omitted for TeamGroup.
        if ($SharePointObj.siteDesign.value) { $SiteParams.SiteDesign = $SharePointObj.siteDesign.value }
        $Result = New-CIPPSharepointSite @SiteParams
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
