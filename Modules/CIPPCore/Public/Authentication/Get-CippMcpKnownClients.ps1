function Get-CippMcpKnownClients {
    <#
    .SYNOPSIS
        Returns the OAuth artifacts of well-known MCP clients supported by CIPP.
    .DESCRIPTION
        Single source of truth for the callback URLs and first-party client IDs of the MCP
        clients CIPP pre-registers on the MCP resource app (Claude, ChatGPT, VS Code /
        GitHub Copilot, Copilot Studio / M365 Copilot). Set-CIPPMCPClientApp writes these to
        the app registration and Set-CippApiAuth allows the first-party clients in EasyAuth,
        so connecting a client never requires manual portal changes.

        - WebRedirectUris: browser/server-side callback URLs. These clients authenticate with
          this app's own client ID, so their callbacks must be registered as web redirect URIs.
        - PublicClientRedirectUris: loopback redirects for desktop/CLI clients. Entra ignores
          the port component on http://127.0.0.1 loopback redirects, which covers VS Code
          (port 33418) and Copilot CLI (random port) without per-port registration.
        - PreAuthorizedClientIds: first-party Entra applications that bring their own client ID
          (VS Code, also used by GitHub Copilot Chat). These need pre-authorization on the
          user_impersonation scope and an EasyAuth allowedApplications entry, not a redirect URI.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    [PSCustomObject]@{
        WebRedirectUris          = @(
            # Claude (claude.ai today; Anthropic documents claude.com as its successor)
            'https://claude.ai/api/mcp/auth_callback'
            'https://claude.com/api/mcp/auth_callback'
            # ChatGPT connectors
            'https://chatgpt.com/connector_platform_oauth_redirect'
            # VS Code (stable + insiders) web callback used by its MCP OAuth flow
            'https://vscode.dev/redirect'
            'https://insiders.vscode.dev/redirect'
            # Copilot Studio / M365 Copilot agents (Power Platform connector redirect)
            'https://global.consent.azure-apim.net/redirect'
        )
        PublicClientRedirectUris = @(
            'http://127.0.0.1'
        )
        PreAuthorizedClientIds   = @(
            # Visual Studio Code (first-party; also used by GitHub Copilot Chat in VS Code)
            'aebc6443-996d-45c2-90f0-388ff96faa56'
        )
    }
}
