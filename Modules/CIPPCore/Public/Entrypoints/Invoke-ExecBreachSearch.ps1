using namespace System.Net

function Invoke-ExecBreachSearch {
    <#
    .SYNOPSIS
    Execute breach search for a tenant
    
    .DESCRIPTION
    Initiates a background breach search for a specific tenant using the Have I Been Pwned API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Security
    Summary: Exec Breach Search
    Description: Initiates a background breach search for a specific tenant using the Have I Been Pwned API to check for compromised accounts and domains
    Tags: Security,Breaches,HIBP,Background Job
    Parameter: tenantFilter (string) [query] - Target tenant identifier to search for breaches
    Response: Returns a response object with the following properties:
    Response: - Results (string): Confirmation message that the search has been initiated
    Response: Example: {
      "Results": "Executing Search for contoso.onmicrosoft.com"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.query.tenantFilter

    #Move to background job
    New-BreachTenantSearch -TenantFilter $TenantFilter
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = "Executing Search for $TenantFilter" }
        })

}
