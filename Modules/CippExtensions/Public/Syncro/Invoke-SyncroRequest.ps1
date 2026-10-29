function Invoke-SyncroRequest {
    <#
    .SYNOPSIS
        Sends one request to the Syncro REST API using the stored integration credentials.
    .DESCRIPTION
        Syncro authenticates with a per-user API key sent as a bearer token against
        https://{subdomain}.syncromsp.com/api/v1. The subdomain setting accepts either the bare
        subdomain ("contoso") or a pasted URL ("https://contoso.syncromsp.com/..."); both are
        reduced to the subdomain here so an admin can copy whatever their browser shows.

        The API key is read from the extension secret store, never from the configuration row,
        so a configuration object alone cannot authenticate.
    .PARAMETER Configuration
        The Syncro block of the extension configuration. Only Subdomain is read.
    .PARAMETER Endpoint
        Path under /api/v1, e.g. '/customers' or '/tickets'.
    .PARAMETER Method
        HTTP method. Defaults to GET.
    .PARAMETER Query
        Hashtable of query string parameters.
    .PARAMETER Body
        Object to serialise as the JSON request body for POST/PUT.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Configuration,
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',
        [hashtable]$Query,
        $Body
    )

    $Subdomain = Get-SyncroSubdomain -Subdomain $Configuration.Subdomain
    if ([string]::IsNullOrWhiteSpace($Subdomain)) {
        throw 'Syncro is not configured: the Syncro Subdomain setting is empty.'
    }

    $APIKey = Get-ExtensionAPIKey -Extension 'Syncro'
    if ([string]::IsNullOrWhiteSpace($APIKey)) {
        throw 'Syncro is not configured: no API key has been saved for the integration.'
    }

    $Uri = "https://$Subdomain.syncromsp.com/api/v1$Endpoint"
    if ($Query -and $Query.Count -gt 0) {
        $Pairs = foreach ($Key in $Query.Keys) {
            '{0}={1}' -f [System.Uri]::EscapeDataString("$Key"), [System.Uri]::EscapeDataString("$($Query[$Key])")
        }
        # Braces are required: "$Uri?" would read a variable literally named 'Uri?'.
        $Uri = "${Uri}?$($Pairs -join '&')"
    }

    $RequestParams = @{
        Uri         = $Uri
        Method      = $Method
        Headers     = @{
            Authorization = "Bearer $APIKey"
            Accept        = 'application/json'
        }
        ContentType = 'application/json; charset=utf-8'
        UserAgent   = Get-CippUserAgent
    }
    if ($null -ne $Body) {
        $RequestParams.Body = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 10 -Compress }
    }

    return Invoke-RestMethod @RequestParams
}
