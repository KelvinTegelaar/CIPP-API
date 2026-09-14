function Get-CippMcpScopeAppSettings {
    <#
    .SYNOPSIS
        Builds the App Service settings that advertise the MCP OAuth scopes - the EasyAuth
        challenge header plus the protected-resource / authorization-server discovery documents -
        so a client requests offline_access and Entra issues a refresh token.
    .DESCRIPTION
        Single source of truth for WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES and, on CIPPNG/Craft, the
        CRAFT_PRM and CRAFT_PRM_AS documents. Both Invoke-ExecApiClient (Save to Azure) and the
        Initialize-CIPPAuth warmup reconcile write these; defining the values here means the two
        callers cannot drift apart and fight each other with a restart on every warmup.

        offline_access is the load-bearing scope. Without it in the advertised scope set, strict
        discovery clients - e.g. GitHub Copilot CLI, which reads the scope only from the challenge
        header and never falls back to the discovery docs - never request it, so Entra never issues
        a refresh token and the client re-authenticates roughly every hour. (Copilot Studio uses
        Manual OAuth and ignores all of this; its refresh depends on app-registration consent.)
    .PARAMETER Hostname
        The App Service hostname (WEBSITE_HOSTNAME) - the *.azurewebsites.net host that matches the
        MCP client app registration's identifier URIs, not the vanity domain.
    .PARAMETER TenantId
        Partner tenant ID, used to build the tenanted authorization-server endpoints.
    .PARAMETER IsCippNg
        When set, also emits the CRAFT_PRM / CRAFT_PRM_AS discovery documents (CIPPNG/Craft only).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Hostname,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [switch]$IsCippNg
    )

    $McpScope = "https://$Hostname/user_impersonation"
    $McpScopesSupported = @('openid', 'profile', 'offline_access', $McpScope)

    $Settings = @{
        'WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES' = 'openid profile offline_access {0}' -f $McpScope
    }

    if ($IsCippNg) {
        $TenantedLogin = "https://login.microsoftonline.com/$TenantId"
        $Settings['CRAFT_PRM'] = [ordered]@{
            resource                 = '{origin}/api/ExecMcp'
            authorization_servers    = @('{origin}')
            scopes_supported         = $McpScopesSupported
            bearer_methods_supported = @('header')
        } | ConvertTo-Json -Compress
        $Settings['CRAFT_PRM_AS'] = [ordered]@{
            issuer                                = '{origin}'
            authorization_endpoint                = "$TenantedLogin/oauth2/v2.0/authorize"
            token_endpoint                        = "$TenantedLogin/oauth2/v2.0/token"
            jwks_uri                              = "$TenantedLogin/discovery/v2.0/keys"
            registration_endpoint                 = '{origin}/api/PublicMcpRegister'
            response_types_supported              = @('code')
            response_modes_supported              = @('query', 'form_post')
            grant_types_supported                 = @('authorization_code', 'refresh_token')
            code_challenge_methods_supported      = @('S256')
            token_endpoint_auth_methods_supported = @('none', 'client_secret_post', 'client_secret_basic')
            scopes_supported                      = $McpScopesSupported
        } | ConvertTo-Json -Compress
    }

    return $Settings
}
