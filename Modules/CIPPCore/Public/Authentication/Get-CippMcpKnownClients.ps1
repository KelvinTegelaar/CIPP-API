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

        Which platform bucket a redirect URI is registered under decides how Entra treats the
        token exchange, and getting it wrong fails at the very last step of the flow:

        - PublicClientRedirectUris -> 'publicClient' ("Mobile and desktop applications").
          For clients that redeem the code with PKCE, no client secret, and no Origin header
          (server-side redemption) — which is what Claude and ChatGPT do, and what loopback CLI
          clients do. This is the ONLY platform that permits that combination: 'web' rejects the
          secret-less exchange with AADSTS7000218, and 'spa' rejects the non-browser exchange with
          AADSTS9002327 ("may only be redeemed via cross-origin requests"). Verified end-to-end
          with Claude, Aug 7 2026. Entra ignores the port on http://127.0.0.1, so one loopback
          entry covers VS Code (33418) and Copilot CLI (random ports).
        - ConfidentialRedirectUris -> 'web'. For clients that authenticate with a client secret,
          i.e. the Power Platform connector behind Copilot Studio / M365 Copilot agents, whose
          wizard collects a client ID and secret.
        - PreAuthorizedClientIds: first-party Entra applications that bring their own client ID
          (VS Code, also used by GitHub Copilot Chat). These need pre-authorization on the
          user_impersonation scope and an EasyAuth allowedApplications entry, not a redirect URI.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    [PSCustomObject]@{
        PublicClientRedirectUris = @(
            # Claude (claude.ai today; Anthropic documents claude.com as its successor)
            'https://claude.ai/api/mcp/auth_callback'
            'https://claude.com/api/mcp/auth_callback'
            # ChatGPT connectors
            'https://chatgpt.com/connector_platform_oauth_redirect'
            # VS Code (stable + insiders) web callback, used when it registers dynamically rather
            # than falling back to its first-party client ID below
            'https://vscode.dev/redirect'
            'https://insiders.vscode.dev/redirect'
            # Loopback for desktop/CLI clients (port-agnostic in Entra)
            'http://127.0.0.1'
        )
        ConfidentialRedirectUris = @(
            # Copilot Studio / M365 Copilot agents (Power Platform connector redirect)
            'https://global.consent.azure-apim.net/redirect'
        )
        PreAuthorizedClientIds   = @(
            # Visual Studio Code (first-party; also used by GitHub Copilot Chat in VS Code)
            'aebc6443-996d-45c2-90f0-388ff96faa56'
        )
    }
}
