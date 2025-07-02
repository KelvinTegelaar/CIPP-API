using namespace System.Net

function Invoke-ListCSPLicenses {
    <#
    .SYNOPSIS
    List CSP licenses for a tenant through Sherweb
    
    .DESCRIPTION
    Retrieves Cloud Solution Provider (CSP) license information for a specific tenant through Sherweb integration, including subscription details and license counts.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
        
    .NOTES
    Group: CSP Management
    Summary: List CSP Licenses
    Description: Retrieves Cloud Solution Provider (CSP) license information for a specific tenant through Sherweb integration, including subscription details and license counts.
    Tags: CSP,Licenses,Sherweb,Subscriptions
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns CSP license data from Sherweb API
    Response: On success: Array of CSP license objects with HTTP 200 status
    Response: On error: Error message with HTTP 400 status
    Response: Error message: "Unable to retrieve CSP licenses, ensure that you have enabled the Sherweb integration and mapped the tenant in the integration settings."
    Example: [
      {
        "subscriptionId": "12345678-1234-1234-1234-123456789012",
        "subscriptionName": "Microsoft 365 Business Premium",
        "skuId": "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46",
        "quantity": 25,
        "status": "Active",
        "startDate": "2024-01-01T00:00:00Z",
        "endDate": "2024-12-31T23:59:59Z"
      }
    ]
    Error: Returns error details if the operation fails to retrieve CSP licenses.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $Result = Get-SherwebCurrentSubscription -TenantFilter $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Result = 'Unable to retrieve CSP licenses, ensure that you have enabled the Sherweb integration and mapped the tenant in the integration settings.'
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Result)
        }) -Clobber

}
