function Get-SharePointAdminLink {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param ($Public, $TenantFilter)

    if ($Public) {
        # Do it through domain discovery, unreliable
        try {
            # Get tenant information using autodiscover
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
                <Domain>$TenantFilter</Domain>
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

            # Invoke autodiscover
            $Response = Invoke-RestMethod -UseBasicParsing -Method Post -Uri 'https://autodiscover-s.outlook.com/autodiscover/autodiscover.svc' -Body $body -Headers $AutoDiscoverHeaders

            # Get the onmicrosoft.com domain from the response
            $TenantDomains = $Response.Envelope.body.GetFederationInformationResponseMessage.response.Domains.Domain | Sort-Object
            $OnMicrosoftDomains = $TenantDomains | Where-Object { $_ -like '*.onmicrosoft.com' }

            if ($OnMicrosoftDomains.Count -eq 0) {
                throw 'Could not find onmicrosoft.com domain through autodiscover'
            } elseif ($OnMicrosoftDomains.Count -gt 1) {
                throw "Multiple onmicrosoft.com domains found through autodiscover. Cannot determine the correct one: $($OnMicrosoftDomains -join ', ')"
            } else {
                $OnMicrosoftDomain = $OnMicrosoftDomains[0]
                $tenantName = $OnMicrosoftDomain.Split('.')[0]
            }
        } catch {
            throw "Failed to get SharePoint admin URL through autodiscover: $($_.Exception.Message)"
        }
    } else {
        $tenantName = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter).id.Split('.')[0]
    }

    # Return object with all needed properties
    return [PSCustomObject]@{
        AdminUrl      = "https://$tenantName-admin.sharepoint.com"
        TenantName    = $tenantName
        SharePointUrl = "https://$tenantName.sharepoint.com"
    }
}
