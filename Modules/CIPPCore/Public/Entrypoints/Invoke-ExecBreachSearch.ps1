using namespace System.Net

Function Invoke-ExecBreachSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantFilter = $Request.query.TenantFilter
    #Move to background job
    New-BreachTenantSearch -TenantFilter $TenantFilter
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = "Executing Search for $TenantFilter" }
        })

}
