function Invoke-ExecExtensionOAuth {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Extension.ReadWrite
    .DESCRIPTION
        Authorization-code sign-in for an extension that needs a user-context token. Action is one of
        start (returns the vendor authorize URL), exchange (code + state to a stored refresh token),
        status (who is connected) or disconnect. The browser side is the /authredirect popup relay.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Extension = $Request.Body.Extension ?? $Request.Query.Extension
    $Action = $Request.Body.Action ?? $Request.Query.Action
    $StatusCode = [HttpStatusCode]::OK

    # Only vendors listed here can be connected; token URLs never come from the request.
    $Providers = @{
        NinjaOne = @{
            Scope      = 'monitoring management offline_access'
            SecretName = 'NinjaOneRefreshToken'
        }
    }

    try {
        if (-not $Providers.ContainsKey("$Extension")) { throw "Extension '$Extension' does not support OAuth sign-in." }
        $Provider = $Providers["$Extension"]
        $ConfigTable = Get-CIPPTable -TableName Extensionsconfig
        $Configuration = ((Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json).$Extension
        $Instance = $Configuration.Instance -replace '/ws', '' -replace 'https://', ''
        $OAuthTable = Get-CIPPTable -TableName ExtensionOAuth

        # The popup relays the code over a same-origin BroadcastChannel, so the redirect must be
        # the origin the settings page is open on, scheme and port included, not a canonical
        # hostname. The browser's own Origin header is that; x-ms-original-url is last because a
        # proxy can rewrite its scheme.
        $Origin = $null
        foreach ($Candidate in @($Headers.origin, $Headers.referer, $Headers.'x-ms-original-url')) {
            if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
            try { $Origin = ([System.Uri]$Candidate).GetLeftPart([System.UriPartial]::Authority); break } catch { continue }
        }
        if (-not $Origin) { throw 'Could not determine the CIPP URL for the redirect.' }
        $RedirectUri = "$Origin/authredirect"

        $Results = switch ($Action) {
            'start' {
                if (-not $Configuration.ClientID -or -not $Instance) { throw "The $Extension integration needs an instance and client id saved first." }
                $Bytes = [byte[]]::new(16)
                [System.Security.Cryptography.RandomNumberGenerator]::Fill($Bytes)
                $State = [Convert]::ToHexString($Bytes).ToLowerInvariant()
                Add-CIPPAzDataTableEntity @OAuthTable -Entity @{
                    PartitionKey = 'State'
                    RowKey       = $State
                    Extension    = "$Extension"
                    Created      = [datetime]::UtcNow.ToString('o')
                } -Force
                $Query = @(
                    'response_type=code'
                    "client_id=$([System.Uri]::EscapeDataString($Configuration.ClientID))"
                    "redirect_uri=$([System.Uri]::EscapeDataString($RedirectUri))"
                    "scope=$([System.Uri]::EscapeDataString($Provider.Scope))"
                    "state=$State"
                ) -join '&'
                @{
                    authorizeUrl = "https://$Instance/ws/oauth/authorize?$Query"
                    redirectUri  = $RedirectUri
                }
            }
            'exchange' {
                $State = "$($Request.Body.state)"
                $Code = "$($Request.Body.code)"
                if (-not $State -or -not $Code) { throw 'code and state are required.' }
                $StateRow = Get-CIPPAzDataTableEntity @OAuthTable -Filter "PartitionKey eq 'State' and RowKey eq '$State'"
                if ($StateRow) { Remove-CIPPAzDataTableEntity @OAuthTable -Entity $StateRow -Force }
                if (-not $StateRow -or $StateRow.Extension -ne "$Extension" -or ([datetime]::UtcNow - [datetime]::Parse($StateRow.Created).ToUniversalTime()).TotalMinutes -gt 10) {
                    throw 'The sign-in state is unknown or expired. Start the sign-in again.'
                }
                $Body = @{
                    grant_type    = 'authorization_code'
                    client_id     = $Configuration.ClientID
                    client_secret = (Get-ExtensionAPIKey -Extension "$Extension")
                    code          = $Code
                    redirect_uri  = $RedirectUri
                }
                $Token = Invoke-RestMethod -Uri "https://$Instance/ws/oauth/token" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'
                if (-not $Token.refresh_token) { throw 'The vendor did not return a refresh token. Check the API client allows the Authorization Code grant and offline access.' }
                $null = Set-ExtensionAPIKey -Extension $Provider.SecretName -APIKey $Token.refresh_token
                Add-CIPPAzDataTableEntity @OAuthTable -Entity @{
                    PartitionKey = 'Connection'
                    RowKey       = "$Extension"
                    ConnectedAt  = [datetime]::UtcNow.ToString('o')
                    Scope        = "$($Token.scope ?? $Provider.Scope)"
                } -Force
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$Extension ticketing connected with a user sign-in" -Sev 'Info'
                @{ Results = "$Extension is connected. Tickets will be raised as the user that signed in." }
            }
            'status' {
                $Row = Get-CIPPAzDataTableEntity @OAuthTable -Filter "PartitionKey eq 'Connection' and RowKey eq '$Extension'"
                @{
                    connected   = [bool]$Row
                    connectedAt = $Row.ConnectedAt
                    scope       = $Row.Scope
                    redirectUri = $RedirectUri
                }
            }
            'disconnect' {
                $null = Remove-ExtensionAPIKey -Extension $Provider.SecretName
                $Row = Get-CIPPAzDataTableEntity @OAuthTable -Filter "PartitionKey eq 'Connection' and RowKey eq '$Extension'"
                if ($Row) { Remove-CIPPAzDataTableEntity @OAuthTable -Entity $Row -Force }
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$Extension ticketing sign-in removed" -Sev 'Info'
                @{ Results = "$Extension sign-in removed." }
            }
            default { throw "Unknown action '$Action'." }
        }
    } catch {
        $StatusCode = [HttpStatusCode]::BadRequest
        $Message = if ($_.ErrorDetails.Message) { Get-NormalizedError -Message $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "$Extension OAuth $Action failed: $Message" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $Results = @{ Results = "Failed: $Message" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
