using namespace System.Net

function Invoke-ListPartnerRelationships {
    <#
    .SYNOPSIS
    List partner relationships and cross-tenant access policies
    
    .DESCRIPTION
    Retrieves partner relationships and cross-tenant access policies for a tenant using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
        
    .NOTES
    Group: Tenant Management
    Summary: List Partner Relationships
    Description: Retrieves partner relationships and cross-tenant access policies for a tenant using Microsoft Graph API with reverse tenant lookup capabilities
    Tags: Tenant Management,Partner Relationships,Cross-Tenant Access,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns an object with the following properties:
    Response: - Results (array): Array of partner relationship objects
    Response: Each partner object contains:
    Response: - tenantId (string): Partner tenant ID
    Response: - displayName (string): Partner display name
    Response: - tenantType (string): Partner tenant type
    Response: - inboundTrust (object): Inbound trust settings
    Response: - outboundTrust (object): Outbound trust settings
    Response: On success: Array of partner relationships with HTTP 200 status
    Response: On error: Empty array with HTTP 403 status
    Example: {
      "Results": [
        {
          "tenantId": "87654321-4321-4321-4321-210987654321",
          "displayName": "Partner Organization",
          "tenantType": "AAD",
          "inboundTrust": {
            "isInboundAllowed": true,
            "isMfaRequired": false
          },
          "outboundTrust": {
            "isOutboundAllowed": true,
            "isMfaRequired": false
          }
        }
      ]
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GraphRequestList = @{
            Endpoint            = 'policies/crossTenantAccessPolicy/partners'
            TenantFilter        = $TenantFilter
            QueueNameOverride   = 'Partner Relationships'
            ReverseTenantLookup = $true
        }
        $GraphRequest = Get-GraphRequestList @GraphRequestList
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $GraphRequest = @()
        $StatusCode = [HttpStatusCode]::Forbidden
    }


    $Results = [PSCustomObject]@{
        Results = @($GraphRequest)
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
