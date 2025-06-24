using namespace System.Net

Function Invoke-AddSite {
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


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $SharePointObj = $Request.Body

    try {
        $Result = New-CIPPSharepointSite -Headers $Headers -SiteName $SharePointObj.siteName -SiteDescription $SharePointObj.siteDescription -SiteOwner $SharePointObj.siteOwner.value -TemplateName $SharePointObj.templateName.value -SiteDesign $SharePointObj.siteDesign.value -SensitivityLabel $SharePointObj.sensitivityLabel -TenantFilter $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = "Failed to create SharePoint Site: $($_.Exception.Message)"
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
