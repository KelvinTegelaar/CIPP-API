function Set-CIPPMCPClientApp {
    <#
    .SYNOPSIS
        Configures an API client's app registration to act as the MCP OAuth resource.
    .DESCRIPTION
        Adds the host-based MCP identifier URIs, forces v2 tokens, ensures the
        user_impersonation scope, and pre-registers the well-known MCP clients from
        Get-CippMcpKnownClients: their callback URLs as redirect URIs, loopback redirects
        for desktop/CLI clients, and pre-authorization for first-party clients (VS Code)
        so no manual app registration changes are needed to connect a client.
    .PARAMETER AppId
        Application (client) ID of the API client to configure.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,
        $Headers
    )

    $Hostname = $env:WEBSITE_HOSTNAME
    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        throw 'WEBSITE_HOSTNAME is not set; cannot determine the MCP resource URL.'
    }

    $McpUris = @("https://$Hostname", "https://$Hostname/api/ExecMcp")

    $App = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')" -NoAuthCheck $true -AsApp $true
    if (-not $App) {
        throw "App registration with AppId '$AppId' was not found."
    }

    # Merge identifier URIs, preserving existing (e.g. api://<appId>)
    $IdentifierUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.identifierUris)) {
        if (-not [string]::IsNullOrWhiteSpace($Uri) -and $IdentifierUris -notcontains $Uri) { $IdentifierUris.Add($Uri) }
    }
    foreach ($Uri in $McpUris) {
        if ($IdentifierUris -notcontains $Uri) { $IdentifierUris.Add($Uri) }
    }

    # Preserve the existing api object; force v2 tokens; ensure a user_impersonation delegated scope
    $Api = if ($App.api) { $App.api | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable } else { @{} }
    $Api.requestedAccessTokenVersion = 2
    $Scopes = [System.Collections.Generic.List[object]]::new()
    if ($Api.oauth2PermissionScopes) {
        foreach ($Scope in $Api.oauth2PermissionScopes) { $Scopes.Add($Scope) }
    }
    if (-not ($Scopes | Where-Object { $_.value -eq 'user_impersonation' })) {
        $Scopes.Add(@{
                adminConsentDescription = 'Allow the application to access CIPP-API on behalf of the signed-in user.'
                adminConsentDisplayName = 'Access CIPP-API'
                id                      = [guid]::NewGuid().ToString()
                isEnabled               = $true
                type                    = 'User'
                userConsentDescription  = 'Allow the application to access CIPP-API on your behalf.'
                userConsentDisplayName  = 'Access CIPP-API'
                value                   = 'user_impersonation'
            })
    }
    $Api.oauth2PermissionScopes = @($Scopes)

    $KnownClients = Get-CippMcpKnownClients
    $UserImpersonationScope = $Scopes | Where-Object { $_.value -eq 'user_impersonation' } | Select-Object -First 1

    # Pre-authorize first-party MCP clients (e.g. VS Code) on the user_impersonation scope so
    # they can sign users in without a consent prompt. The other known clients (Claude, ChatGPT,
    # Copilot Studio) use this app's own client ID and need their callback URLs registered instead.
    $PreAuthorized = [System.Collections.Generic.List[object]]::new()
    if ($Api.preAuthorizedApplications) {
        foreach ($Entry in $Api.preAuthorizedApplications) { $PreAuthorized.Add($Entry) }
    }
    foreach ($KnownAppId in $KnownClients.PreAuthorizedClientIds) {
        $Existing = $PreAuthorized | Where-Object { $_.appId -eq $KnownAppId } | Select-Object -First 1
        if ($Existing) {
            if (@($Existing.delegatedPermissionIds) -notcontains $UserImpersonationScope.id) {
                $PermissionIds = [System.Collections.Generic.List[string]]::new()
                foreach ($Id in @($Existing.delegatedPermissionIds)) {
                    if (-not [string]::IsNullOrWhiteSpace($Id)) { $PermissionIds.Add($Id) }
                }
                $PermissionIds.Add($UserImpersonationScope.id)
                $Existing.delegatedPermissionIds = @($PermissionIds)
            }
        } else {
            $PreAuthorized.Add(@{
                    appId                  = $KnownAppId
                    delegatedPermissionIds = @($UserImpersonationScope.id)
                })
        }
    }
    $Api.preAuthorizedApplications = @($PreAuthorized)

    # Register the callback URLs of known MCP clients under the platform each client's token
    # exchange requires — see Get-CippMcpKnownClients for why the bucket decides success. Every
    # list below is rebuilt from the live app so a URI that an earlier version filed under the
    # wrong platform is moved rather than duplicated (Entra rejects the same URI twice).
    $PublicRedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.publicClient.redirectUris)) {
        if (-not [string]::IsNullOrWhiteSpace($Uri) -and $PublicRedirectUris -notcontains $Uri) { $PublicRedirectUris.Add($Uri) }
    }
    foreach ($Uri in $KnownClients.PublicClientRedirectUris) {
        if ($PublicRedirectUris -notcontains $Uri) { $PublicRedirectUris.Add($Uri) }
    }

    # Web keeps the app's own confidential callbacks — the EasyAuth login callback above all —
    # plus the secret-authenticating clients, minus anything now claimed by another platform.
    $WebRedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.web.redirectUris)) {
        if ([string]::IsNullOrWhiteSpace($Uri) -or $WebRedirectUris -contains $Uri) { continue }
        if ($PublicRedirectUris -contains $Uri) { continue }
        $WebRedirectUris.Add($Uri)
    }
    foreach ($Uri in $KnownClients.ConfidentialRedirectUris) {
        if ($WebRedirectUris -notcontains $Uri -and $PublicRedirectUris -notcontains $Uri) { $WebRedirectUris.Add($Uri) }
    }

    # Nothing of ours belongs under 'spa' (those tokens can only be redeemed cross-origin, which
    # no MCP client does), so preserve any URI the tenant added there but drop ours.
    $SpaRedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.spa.redirectUris)) {
        if ([string]::IsNullOrWhiteSpace($Uri) -or $SpaRedirectUris -contains $Uri) { continue }
        if ($PublicRedirectUris -contains $Uri -or $WebRedirectUris -contains $Uri) { continue }
        $SpaRedirectUris.Add($Uri)
    }

    # Declare offline_access (Microsoft Graph, delegated) so Entra will issue a refresh token to
    # MCP clients. Without it, Copilot Studio (Manual OAuth) and stricter discovery clients
    # re-prompt for sign-in roughly every hour when the access token expires. Additive — every
    # permission already on the app is preserved; only offline_access is added if missing.
    $GraphResourceId = '00000003-0000-0000-c000-000000000000'
    $OfflineAccessId = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'
    $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()
    $GraphEntrySeen = $false
    foreach ($Resource in @($App.requiredResourceAccess)) {
        $ResourceAccess = [System.Collections.Generic.List[object]]::new()
        foreach ($Access in @($Resource.resourceAccess)) { $ResourceAccess.Add(@{ id = $Access.id; type = $Access.type }) }
        if ($Resource.resourceAppId -eq $GraphResourceId) {
            $GraphEntrySeen = $true
            if (-not ($ResourceAccess | Where-Object { $_.id -eq $OfflineAccessId })) {
                $ResourceAccess.Add(@{ id = $OfflineAccessId; type = 'Scope' })
            }
        }
        $RequiredResourceAccess.Add(@{ resourceAppId = $Resource.resourceAppId; resourceAccess = @($ResourceAccess) })
    }
    if (-not $GraphEntrySeen) {
        $RequiredResourceAccess.Add(@{ resourceAppId = $GraphResourceId; resourceAccess = @(@{ id = $OfflineAccessId; type = 'Scope' }) })
    }

    $PatchBody = @{
        identifierUris         = @($IdentifierUris)
        api                    = $Api
        web                    = @{ redirectUris = @($WebRedirectUris) }
        spa                    = @{ redirectUris = @($SpaRedirectUris) }
        publicClient           = @{ redirectUris = @($PublicRedirectUris) }
        requiredResourceAccess = @($RequiredResourceAccess)
        # "Allow public client flows" — required for the secret-less PKCE redemption every MCP
        # client above performs.
        isFallbackPublicClient = $true
    } | ConvertTo-Json -Depth 10 -Compress

    if ($PSCmdlet.ShouldProcess($AppId, 'Configure app registration for MCP')) {
        try {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($App.id)" -type PATCH -body $PatchBody -NoAuthCheck $true -asapp $true
            Write-LogMessage -headers $Headers -API 'ExecApiClient' -message "Configured app registration $AppId as MCP resource (identifier URIs, v2 tokens, known MCP client callbacks + pre-authorization)." -Sev 'Info'

            # Admin-consent the OIDC + offline_access delegated scopes for this app so Entra
            # issues the refresh token without a per-user consent prompt. Copilot Studio uses
            # Manual OAuth and never reads the challenge/discovery scope, so this app-registration
            # consent — not WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES — is what makes its refresh work.
            # Best-effort: the app still works without it (users may see a one-time prompt, or the
            # grant is retried the next time the client is saved), so a failure here is non-fatal.
            try {
                $ConsentResult = Grant-CippAppGraphConsent -AppId $AppId -Scopes @('openid', 'profile', 'offline_access')
                Write-Information "[MCP-Client] offline_access admin-consent for $AppId : $($ConsentResult.Action)"
            } catch {
                Write-LogMessage -headers $Headers -API 'ExecApiClient' -message "MCP client $AppId configured, but admin-consent for offline_access could not be written (refresh tokens may prompt on first use): $($_.Exception.Message)" -Sev 'Warning'
            }

            return @{ Success = $true; IdentifierUris = @($IdentifierUris); RedirectUris = @($PublicRedirectUris) }
        } catch {
            $ErrMsg = $_.Exception.Message
            if ($ErrMsg -match 'identifierUri' -or $ErrMsg -match 'already exists' -or $ErrMsg -match 'in use') {
                throw "The MCP resource URIs are already assigned to another application. Only one API client can be the MCP resource client. ($ErrMsg)"
            }
            throw
        }
    }
}
