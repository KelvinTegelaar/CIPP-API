using namespace System.Net

function Invoke-ListNamedLocations {
    <#
    .SYNOPSIS
    List Conditional Access named locations
    
    .DESCRIPTION
    Retrieves Conditional Access named locations including IP ranges and countries/regions using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
        
    .NOTES
    Group: Conditional Access
    Summary: List Named Locations
    Description: Retrieves Conditional Access named locations including IP ranges and countries/regions using Microsoft Graph API for conditional access policy configuration
    Tags: Conditional Access,Named Locations,IP Ranges,Countries
    Parameter: TenantFilter (string) [query] - Target tenant identifier
    Response: Returns an array of named location objects with the following properties:
    Response: - id (string): Named location unique identifier
    Response: - displayName (string): Named location display name
    Response: - isTrusted (boolean): Whether the location is trusted
    Response: - ipRanges (array): Array of IP ranges with cidrAddress
    Response: - countriesAndRegions (array): Array of country/region codes
    Response: - rangeOrLocation (string): Formatted string of IP ranges or countries
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "id": "12345678-1234-1234-1234-123456789012",
        "displayName": "Office Network",
        "isTrusted": true,
        "ipRanges": [
          {
            "cidrAddress": "192.168.1.0/24"
          }
        ],
        "rangeOrLocation": "192.168.1.0/24"
      },
      {
        "id": "87654321-4321-4321-4321-210987654321",
        "displayName": "United States",
        "isTrusted": false,
        "countriesAndRegions": ["US"],
        "rangeOrLocation": "US"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'




    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $GraphRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -Tenantid $tenantfilter | Select-Object *,
        @{
            name       = 'rangeOrLocation'
            expression = { if ($_.ipRanges) { $_.ipranges.cidrAddress -join ', ' } else { $_.countriesAndRegions -join ', ' } }
        }
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage

    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
