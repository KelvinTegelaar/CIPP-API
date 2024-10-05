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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    $Results = [System.Collections.ArrayList]@()

    foreach ($sharepointObj in $Request.body.BulkSite) {
        try {
            $SharePointSite = New-CIPPSharepointSite -SiteName $SharePointObj.siteName -SiteDescription $SharePointObj.siteDescription -SiteOwner $SharePointObj.siteOwner -TemplateName $SharePointObj.templateName -SiteDesign $SharePointObj.siteDesign -SensitivityLabel $SharePointObj.sensitivityLabel -TenantFilter $Request.body.TenantFilter
            $Results.add($SharePointSite)
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($userobj.tenantid) -message "Adding SharePoint Site failed. Error: $($_.Exception.Message)" -Sev 'Error'
            $Results.add("Failed to create $($sharepointObj.siteName) Error message: $($_.Exception.Message)")
        }
    }
    $Body = [pscustomobject]@{'Results' = $Results }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
