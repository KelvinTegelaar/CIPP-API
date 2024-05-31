using namespace System.Net

Function Invoke-ListExternalTenantInfo {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $Tenant = $request.query.tenant

    # Normalize to tenantid and determine if tenant exists
    $TenantId = (Invoke-RestMethod -Method GET "https://login.windows.net/$tenant/.well-known/openid-configuration").token_endpoint.Split('/')[3]

    if ($TenantId) {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$TenantId')" -noauthcheck $true -tenantid $TenantFilter
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
        $headers = @{
            'Content-Type' = 'text/xml; charset=utf-8'
            'SOAPAction'   = '"http://schemas.microsoft.com/exchange/2010/Autodiscover/Autodiscover/GetFederationInformation"'
            'User-Agent'   = 'AutodiscoverClient'
        }

        # Invoke
        $response = Invoke-RestMethod -UseBasicParsing -Method Post -Uri 'https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc' -Body $body -Headers $headers

        # Return
        $TenantDomains = $response.Envelope.body.GetFederationInformationResponseMessage.response.Domains.Domain | Sort-Object
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
