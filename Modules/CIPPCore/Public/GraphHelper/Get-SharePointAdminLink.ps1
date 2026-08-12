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

            # Get the onmicrosoft domain from the response. Sovereign clouds use their own
            # suffix (onmicrosoft.de, onmicrosoft.us, partner.onmschina.cn), so don't filter on '.com'.
            $TenantDomains = $Response.Envelope.body.GetFederationInformationResponseMessage.response.Domains.Domain | Sort-Object
            # @() matters: a single match comes back as a bare string, and indexing a string with
            # [0] yields a [char], which then has no .Split().
            $OnMicrosoftDomains = @($TenantDomains | Where-Object { $_ -like '*.onmicrosoft.*' -or $_ -like '*.onmschina.cn' })

            if ($OnMicrosoftDomains.Count -eq 0) {
                throw 'Could not find onmicrosoft domain through autodiscover'
            } elseif ($OnMicrosoftDomains.Count -gt 1) {
                throw "Multiple onmicrosoft domains found through autodiscover. Cannot determine the correct one: $($OnMicrosoftDomains -join ', ')"
            } else {
                $OnMicrosoftDomain = $OnMicrosoftDomains[0]
                $tenantName = $OnMicrosoftDomain.Split('.')[0]
                # Best-effort mapping of the tenant domain suffix to the SharePoint one. Autodiscover
                # cannot tell GCC High (sharepoint.us) from DoD (sharepoint-mil.us) - both are
                # onmicrosoft.us - so DoD needs the Graph path below.
                $SharePointDomain = Get-CIPPSharePointDomain -TenantDomain $OnMicrosoftDomain
            }
        } catch {
            throw "Failed to get SharePoint admin URL through autodiscover: $($_.Exception.Message)"
        }
    } else {
        # id looks like 'contoso.sharepoint.com,<guid>,<guid>' - the host's first label is the name,
        # and the rest is the SharePoint domain. That domain is not always 'sharepoint.com':
        # sovereign clouds use sharepoint.de (Germany), sharepoint.cn (21Vianet),
        # sharepoint.us (GCC High) and sharepoint-mil.us (DoD), so take it from the host we got
        # back rather than assuming.
        $RootSite = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/root' -asApp $true -tenantid $TenantFilter
        $SharePointHost = $RootSite.siteCollection.hostname
        if ([string]::IsNullOrWhiteSpace($SharePointHost)) { $SharePointHost = ($RootSite.id -split ',')[0] }
        if ([string]::IsNullOrWhiteSpace($SharePointHost) -and $RootSite.webUrl) { $SharePointHost = ([uri]$RootSite.webUrl).Host }

        $tenantName = ($SharePointHost -split '\.')[0]
        if ($SharePointHost -match '^[^.]+\.(?<Domain>sharepoint(?:-[a-z]+)?\.[a-z.]+)$') {
            $SharePointDomain = $Matches.Domain
        }
    }

    # Without a name every URL below is a well-formed link to nowhere ('https://-admin.sharepoint.com').
    # Callers cache what they get back, so a bad value here sticks around - fail instead.
    if ([string]::IsNullOrWhiteSpace($tenantName)) {
        throw "Could not determine the SharePoint tenant name for $TenantFilter. The tenant may not have SharePoint provisioned, or the Sites.Read.All permission may be missing."
    }

    # Commercial cloud is the fallback when the host did not look like a SharePoint one.
    if ([string]::IsNullOrWhiteSpace($SharePointDomain)) { $SharePointDomain = 'sharepoint.com' }

    # Return object with all needed properties
    return [PSCustomObject]@{
        AdminUrl         = "https://$tenantName-admin.$SharePointDomain"
        TenantName       = $tenantName
        SharePointUrl    = "https://$tenantName.$SharePointDomain"
        SharePointDomain = $SharePointDomain
    }
}
