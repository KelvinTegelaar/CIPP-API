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

    $SharePointObj = $Request.body

    try {
        $SharePointSite = New-CIPPSharepointSite -SiteName $SharePointObj.siteName -SiteDescription $SharePointObj.siteDescription -SiteOwner $SharePointObj.siteOwner.value -TemplateName $SharePointObj.templateName.value -SiteDesign $SharePointObj.siteDesign.value -SensitivityLabel $SharePointObj.sensitivityLabel -TenantFilter $SharePointObj.tenantFilter
        $body = [pscustomobject]@{'Results' = $SharePointSite }
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($userobj.tenantid) -message "Adding SharePoint Site failed. Error: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. Error message: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
