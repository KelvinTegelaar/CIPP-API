using namespace System.Net

function Invoke-ListOrg {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') {
        $GraphRequest = @()
    } else {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $GraphRequest
    }
}
