function Invoke-PublicMcpRegister {
    <#
    .SYNOPSIS
        Anonymous RFC 7591 dynamic client registration endpoint for MCP clients.
    .DESCRIPTION
        Entra ID offers no registration endpoint, but MCP clients (Claude, ChatGPT, VS Code)
        attempt dynamic client registration as the first step of connecting with only a URL. This
        endpoint closes that gap without any token handling: it validates the requested redirect
        URIs against the known MCP client allowlist and answers with the EXISTING MCP resource app
        registration's client ID as a public (PKCE) client. Nothing is created or modified in
        Entra, and no secret is ever issued — Entra still enforces redirect URIs at authorize time
        and issues all tokens, which EasyAuth validates as always. A client ID is public
        information by OAuth design, so handing it out anonymously discloses nothing sensitive;
        RBAC on the MCP endpoint itself is unchanged.

        Clients find this endpoint via the registration_endpoint field of the authorization server
        metadata document Craft serves from the CRAFT_PRM_AS app setting, which SaveToAzure in
        Invoke-ExecApiClient composes. The route name starts with 'Public' so it rides the existing
        /api/Public* EasyAuth exclusion.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $CorsHeaders = @{
        'Content-Type'                 = 'application/json'
        'Access-Control-Allow-Origin'  = '*'
        'Access-Control-Allow-Methods' = 'POST, OPTIONS'
        'Access-Control-Allow-Headers' = 'Content-Type'
    }

    if ($Request.Method -eq 'OPTIONS') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NoContent; Headers = $CorsHeaders })
    }
    if ($Request.Method -ne 'POST') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::MethodNotAllowed
                Headers    = $CorsHeaders + @{ 'Allow' = 'POST' }
                Body       = (@{ error = 'invalid_client_metadata'; error_description = 'Registration requests must be POSTed as JSON (RFC 7591).' } | ConvertTo-Json -Compress)
            })
    }

    $Body = $Request.Body
    if ($Body -is [string]) {
        try { $Body = $Body | ConvertFrom-Json } catch {
            return (New-CippMcpRegistrationError -Code 'invalid_client_metadata' -Description 'Request body is not valid JSON.' -Headers $CorsHeaders)
        }
    }

    $RedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($Body.redirect_uris)) {
        if (-not [string]::IsNullOrWhiteSpace($Uri)) { $RedirectUris.Add([string]$Uri) }
    }
    if ($RedirectUris.Count -eq 0) {
        return (New-CippMcpRegistrationError -Code 'invalid_redirect_uri' -Description 'redirect_uris is required and must contain at least one URI.' -Headers $CorsHeaders)
    }

    # The "registered client" is always the instance's single MCP resource app registration.
    $Table = Get-CippTable -tablename 'ApiClients'
    $McpClient = Get-CIPPAzDataTableEntity @Table -Filter 'Enabled eq true' |
        Where-Object { "$($_.MCPAllowed)" -eq 'True' } | Select-Object -First 1
    if (-not $McpClient) {
        return (New-CippMcpRegistrationError -Code 'invalid_client_metadata' -Description 'No MCP resource client is configured on this instance. Enable "MCP Access Allowed" on an API client in CIPP and run Save to Azure.' -Headers $CorsHeaders)
    }

    # Known client callbacks and loopback (any port/path) pass directly. Anything else must be a
    # redirect URI on the MCP resource app registration — the same list Entra enforces at
    # authorize time, covering callbacks that can't be enumerated statically (e.g. Copilot
    # Studio's per-connector azure-apim suffix). That lookup is lazy and cached for 60s per
    # runspace: this endpoint is anonymous, so junk-URI spam must not translate into Graph calls.
    $KnownClients = Get-CippMcpKnownClients
    $AllowedCallbacks = @($KnownClients.PublicClientRedirectUris) + @($KnownClients.ConfidentialRedirectUris)
    $ResourceAppCallbacks = $null
    foreach ($Uri in $RedirectUris) {
        $Parsed = $null
        if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$Parsed)) {
            return (New-CippMcpRegistrationError -Code 'invalid_redirect_uri' -Description "Redirect URI '$Uri' is not a valid absolute URI." -Headers $CorsHeaders)
        }
        $IsLoopback = $Parsed.Scheme -eq 'http' -and $Parsed.Host -in @('127.0.0.1', 'localhost', '[::1]')
        if ($IsLoopback -or $AllowedCallbacks -contains $Uri) { continue }

        if ($null -eq $ResourceAppCallbacks) {
            $Cache = $script:McpResourceAppRedirectCache
            if ($Cache -and $Cache.AppId -eq "$($McpClient.RowKey)" -and ([DateTimeOffset]::UtcNow - $Cache.FetchedAt).TotalSeconds -lt 60) {
                $ResourceAppCallbacks = $Cache.Uris
            } else {
                $ResourceAppCallbacks = @()
                try {
                    $ResourceApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($McpClient.RowKey)')?`$select=publicClient,web" -NoAuthCheck $true -AsApp $true
                    $ResourceAppCallbacks = @(@($ResourceApp.publicClient.redirectUris) + @($ResourceApp.web.redirectUris) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                } catch {
                    Write-LogMessage -API 'PublicMcpRegister' -message "Could not read the MCP resource app's redirect URIs; validating against the built-in client list only. Error: $($_.Exception.Message)" -Sev 'Warning'
                }
                # Failures cache as empty so a Graph outage can't be amplified into repeated calls.
                $script:McpResourceAppRedirectCache = @{ AppId = "$($McpClient.RowKey)"; Uris = $ResourceAppCallbacks; FetchedAt = [DateTimeOffset]::UtcNow }
            }
        }
        if ($ResourceAppCallbacks -contains $Uri) { continue }
        return (New-CippMcpRegistrationError -Code 'invalid_redirect_uri' -Description "Redirect URI '$Uri' is not an allowed MCP client callback for this server. To allow a custom client, add its callback to the MCP resource app registration (see the CIPP-API integration docs)." -Headers $CorsHeaders)
    }

    $ClientName = "$($Body.client_name ?? 'MCP client')"
    Write-LogMessage -API 'PublicMcpRegister' -message "MCP client registration served: '$ClientName' -> client_id $($McpClient.RowKey) ($($RedirectUris.Count) redirect URI(s))" -Sev 'Info'

    $Response = [ordered]@{
        client_id                  = "$($McpClient.RowKey)"
        client_id_issued_at        = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        client_name                = $ClientName
        redirect_uris              = @($RedirectUris)
        token_endpoint_auth_method = 'none'
        grant_types                = @('authorization_code', 'refresh_token')
        response_types             = @('code')
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Created
            Headers    = $CorsHeaders
            Body       = ($Response | ConvertTo-Json -Compress)
        })
}
