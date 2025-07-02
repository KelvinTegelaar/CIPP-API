using namespace System.Net

function Invoke-ListExternalTenantInfo {
    <#
    .SYNOPSIS
    List external tenant information and federation domains
    
    .DESCRIPTION
    Retrieves external tenant information using Microsoft Graph API and Exchange Online Autodiscover to get federation domains and tenant details.
    
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
        
    .NOTES
    Group: Tenant Management
    Summary: List External Tenant Info
    Description: Retrieves external tenant information using Microsoft Graph API and Exchange Online Autodiscover service to get federation domains, tenant details, and domain information.
    Tags: Tenant Management,External,Federation,Autodiscover
    Parameter: tenant (string) [query] - Tenant domain or identifier to look up
    Parameter: tenantFilter (string) [query] - Source tenant identifier for the request
    Response: Returns an object with the following properties:
    Response: - GraphRequest (object): Tenant information from Microsoft Graph API including defaultDomainName and other tenant properties
    Response: - Domains (array): Array of federation domains retrieved from Exchange Online Autodiscover
    Response: On success: Tenant information and domains with HTTP 200 status
    Response: On error: May return null or error information
    Example: {
      "GraphRequest": {
        "tenantId": "12345678-1234-1234-1234-123456789012",
        "defaultDomainName": "contoso.com",
        "displayName": "Contoso Corporation",
        "tenantType": "AAD"
      },
      "Domains": [
        "contoso.com",
        "contoso.onmicrosoft.com"
      ]
    }
    Error: Returns error details if the operation fails to retrieve external tenant information.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'



    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Query.tenant
    $TenantFilter = $Request.Query.tenantFilter

    # Normalize to tenantid and determine if tenant exists
    $TenantId = (Invoke-RestMethod -Method GET "https://login.windows.net/$Tenant/.well-known/openid-configuration").token_endpoint.Split('/')[3]

    if ($TenantId) {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$TenantId')" -NoAuthCheck $true -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    }

    if ($GraphRequest) {

        $TenantDefaultDomain = $GraphRequest.defaultDomainName

        $body = @"
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:exm="http://schemas.microsoft.com/exchange/services/2006/messages" xmlns:ext="http://schemas.microsoft.com/exchange/services/2006/types" xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <soap:Header>
        <a:Action soap:mustUnderstand="1">http://schemas.microsoft.com/exchange/2010/Autodiscover/Autodiscover/GetFederationInformation</a:Action>
        <a:To soap:mustUnderstand="1">https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc</a:To>
        <a:ReplyTo>
            <a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address>
        </a:ReplyTo>
    </soap:Header>
    <soap:Body>
        <GetFederationInformationRequestMessage xmlns="http://schemas.microsoft.com/exchange/2010/Autodiscover">
            <Request>
                <Domain>$TenantDefaultDomain</Domain>
            </Request>
        </GetFederationInformationRequestMessage>
    </soap:Body>
</soap:Envelope>
"@

        # Create the headers
        $AutoDiscoverHeaders = @{
            'Content-Type' = 'text/xml; charset=utf-8'
            'SOAPAction'   = '"http://schemas.microsoft.com/exchange/2010/Autodiscover/Autodiscover/GetFederationInformation"'
            'User-Agent'   = 'AutodiscoverClient'
        }

        # Invoke
        $Response = Invoke-RestMethod -UseBasicParsing -Method Post -Uri 'https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc' -Body $body -Headers $AutoDiscoverHeaders

        # Return
        $TenantDomains = $Response.Envelope.body.GetFederationInformationResponseMessage.response.Domains.Domain | Sort-Object
    }

    $results = [PSCustomObject]@{
        GraphRequest = $GraphRequest
        Domains      = @($TenantDomains)
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $results
        })

}
