using namespace System.Net

function Invoke-AddSite {
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
        $SharePointParams = @{
            Headers          = $Headers
            SiteName         = $SharePointObj.siteName
            SiteDescription  = $SharePointObj.siteDescription
            SiteOwner        = $SharePointObj.siteOwner.value
            TemplateName     = $SharePointObj.templateName.value
            SiteDesign       = $SharePointObj.siteDesign.value
            SensitivityLabel = $SharePointObj.sensitivityLabel
            TenantFilter     = $TenantFilter
        }
        $Result = New-CIPPSharepointSite @SharePointParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Result = $_.Exception.Message
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
