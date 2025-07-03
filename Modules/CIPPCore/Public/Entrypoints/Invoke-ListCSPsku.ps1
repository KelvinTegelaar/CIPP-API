using namespace System.Net

function Invoke-ListCSPsku {
    <#
    .SYNOPSIS
    List CSP SKUs available through Sherweb
    
    .DESCRIPTION
    Retrieves Cloud Solution Provider (CSP) SKU information from Sherweb including current subscriptions or full catalog
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
        
    .NOTES
    Group: CSP Management
    Summary: List CSP SKU
    Description: Retrieves Cloud Solution Provider (CSP) SKU information from Sherweb including current subscriptions or full catalog of available products
    Tags: CSP,SKUs,Sherweb,Catalog
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Parameter: currentSkuOnly (boolean) [query] - Whether to return only current subscriptions (true) or full catalog (false)
    Response: Returns CSP SKU data from Sherweb API
    Response: On success: Array of CSP SKU objects with HTTP 200 status
    Response: On error: Error object with HTTP 500 status containing:
    Response: - name (array): Array with error message
    Response: - sku (string): Exception message
    Example: [
      {
        "name": "Microsoft 365 Business Premium",
        "sku": "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46",
        "description": "Best for businesses that need desktop apps and cloud services",
        "category": "Productivity",
        "availability": "Available"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $CurrentSkuOnly = $Request.Query.currentSkuOnly

    try {
        if ($CurrentSkuOnly) {
            $GraphRequest = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
        }
        else {
            $GraphRequest = Get-SherwebCatalog -TenantFilter $TenantFilter
        }
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $GraphRequest = [PSCustomObject]@{
            name = @(@{value = 'Error getting catalog' })
            sku  = $_.Exception.Message
        }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }) -Clobber

}
