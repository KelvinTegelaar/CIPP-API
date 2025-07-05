using namespace System.Net

function Invoke-ExecBreachSearch {
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

    #Move to background job
    New-BreachTenantSearch -TenantFilter $TenantFilter
    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = "Executing Search for $TenantFilter" }
    }

}
