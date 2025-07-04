using namespace System.Net

function Invoke-ListSharepointSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    #  XXX - Seems to be an unused endpoint? -Bobby

    $TenantFilter = $Request.Query.tenantFilter
    $Request = New-GraphGetRequest -tenantid $TenantFilter -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings'

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Request)
    }

}
