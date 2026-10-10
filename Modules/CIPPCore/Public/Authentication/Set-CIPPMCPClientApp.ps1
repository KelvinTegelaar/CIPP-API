function Set-CIPPMCPClientApp {
    <#
    .SYNOPSIS
        Configures an API client app registration as an MCP OAuth client.
    .DESCRIPTION
        In the split-app model an MCPAllowed API client is one of the apps an AI connector signs in
        AS (the OAuth client), while the dedicated CIPP-MCP app (New-CIPPMcpResourceApp) is the
        protected resource the token is for. Several MCPAllowed clients can coexist, each with its own
        role, IP range, redirect URIs and Conditional Access; every one is in EasyAuth
        allowedApplications and CIPP resolves the caller's role from its appId (azp), so keeping them
        as distinct app registrations is what makes per-client permissions and CA work.

        This ensures the resource app exists, then configures THIS client: the known MCP client
        callbacks (public for the PKCE clients, web for Copilot Studio), "allow public client flows",
        the delegated permissions it needs (Microsoft Graph openid/profile/offline_access and the
        resource's user_impersonation), and tenant-wide admin consent for them. It also strips the
        host identifier URIs from the client if a previous (single-app) setup left them there, so the
        dedicated resource app can own them.
    .PARAMETER AppId
        Application (client) ID of the MCPAllowed API client to configure as an MCP OAuth client.
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
    $GraphResourceId = '00000003-0000-0000-c000-000000000000'
    $OidcScopeIds = @('37f7f235-527c-4136-accd-4a02d197296e', '14dad69e-099b-42c9-810b-d002981feec1', '7427e0e9-2fba-42fe-b0c0-848c9e6a8182')
    $HostUris = @("https://$Hostname", "https://$Hostname/api/ExecMcp")
    $KnownClients = Get-CippMcpKnownClients

    # Ensure the dedicated CIPP-MCP resource app exists; we consent this client on its scope.
    $Resource = New-CIPPMcpResourceApp -Headers $Headers
    $ResourceAppId = $Resource.AppId
    $ResourceObjectId = $Resource.ObjectId
    $ScopeId = $Resource.ScopeId

    $App = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$AppId')" -NoAuthCheck $true -AsApp $true
    if (-not $App) {
        throw "App registration with AppId '$AppId' was not found."
    }

    # Strip the host identifier URIs from the client (a previous single-app setup may have added
    # them); they belong on the dedicated resource app now. Keep everything else (e.g. api://<appId>).
    $IdentifierUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.identifierUris)) {
        if (-not [string]::IsNullOrWhiteSpace($Uri) -and $HostUris -notcontains $Uri -and $IdentifierUris -notcontains $Uri) { $IdentifierUris.Add($Uri) }
    }

    # Redirect URIs: public (PKCE clients) and web (Copilot Studio confidential + the EasyAuth login
    # callback), rebuilt from the live app so a URI filed under the wrong platform is moved, not
    # duplicated. Nothing of ours belongs under 'spa'.
    $PublicRedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.publicClient.redirectUris)) { if (-not [string]::IsNullOrWhiteSpace($Uri) -and $PublicRedirectUris -notcontains $Uri) { $PublicRedirectUris.Add($Uri) } }
    foreach ($Uri in $KnownClients.PublicClientRedirectUris) { if ($PublicRedirectUris -notcontains $Uri) { $PublicRedirectUris.Add($Uri) } }

    $WebRedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.web.redirectUris)) {
        if ([string]::IsNullOrWhiteSpace($Uri) -or $WebRedirectUris -contains $Uri -or $PublicRedirectUris -contains $Uri) { continue }
        $WebRedirectUris.Add($Uri)
    }
    foreach ($Uri in $KnownClients.ConfidentialRedirectUris) { if ($WebRedirectUris -notcontains $Uri -and $PublicRedirectUris -notcontains $Uri) { $WebRedirectUris.Add($Uri) } }

    $SpaRedirectUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.spa.redirectUris)) {
        if ([string]::IsNullOrWhiteSpace($Uri) -or $SpaRedirectUris -contains $Uri -or $PublicRedirectUris -contains $Uri -or $WebRedirectUris -contains $Uri) { continue }
        $SpaRedirectUris.Add($Uri)
    }

    # requiredResourceAccess: preserve existing, ensure Graph OIDC + offline_access, and add the
    # resource app's user_impersonation (delegated) so this client can request a token for it.
    $RequiredResourceAccess = [System.Collections.Generic.List[object]]::new()
    $GraphSeen = $false
    $ResourceSeen = $false
    foreach ($Resource2 in @($App.requiredResourceAccess)) {
        $Access = [System.Collections.Generic.List[object]]::new()
        foreach ($A in @($Resource2.resourceAccess)) { $Access.Add(@{ id = $A.id; type = $A.type }) }
        if ($Resource2.resourceAppId -eq $GraphResourceId) {
            $GraphSeen = $true
            foreach ($Id in $OidcScopeIds) { if (-not ($Access | Where-Object { $_.id -eq $Id })) { $Access.Add(@{ id = $Id; type = 'Scope' }) } }
        } elseif ($Resource2.resourceAppId -eq $ResourceAppId) {
            $ResourceSeen = $true
            if ($ScopeId -and -not ($Access | Where-Object { $_.id -eq $ScopeId })) { $Access.Add(@{ id = $ScopeId; type = 'Scope' }) }
        }
        $RequiredResourceAccess.Add(@{ resourceAppId = $Resource2.resourceAppId; resourceAccess = @($Access) })
    }
    if (-not $GraphSeen) {
        $RequiredResourceAccess.Add(@{ resourceAppId = $GraphResourceId; resourceAccess = @($OidcScopeIds | ForEach-Object { @{ id = $_; type = 'Scope' } }) })
    }
    if (-not $ResourceSeen -and $ScopeId) {
        $RequiredResourceAccess.Add(@{ resourceAppId = $ResourceAppId; resourceAccess = @(@{ id = $ScopeId; type = 'Scope' }) })
    }

    $PatchBody = @{
        identifierUris         = @($IdentifierUris)
        web                    = @{ redirectUris = @($WebRedirectUris) }
        spa                    = @{ redirectUris = @($SpaRedirectUris) }
        publicClient           = @{ redirectUris = @($PublicRedirectUris) }
        requiredResourceAccess = @($RequiredResourceAccess)
        isFallbackPublicClient = $true
    } | ConvertTo-Json -Depth 10 -Compress

    if ($PSCmdlet.ShouldProcess($AppId, 'Configure API client as MCP OAuth client')) {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($App.id)" -type PATCH -body $PatchBody -NoAuthCheck $true -asapp $true
        Write-LogMessage -headers $Headers -API 'ExecApiClient' -message "Configured API client $AppId as an MCP OAuth client (callbacks, public client flows, resource permissions) against resource $ResourceAppId." -Sev 'Info'

        # OIDC + offline_access on Graph are admin-consented tenant-wide (they can't be
        # pre-authorized). The resource's user_impersonation is handled by pre-authorizing this
        # client on the CIPP-MCP resource app instead of a consent grant - that needs no consent at
        # all, so it works even where user consent to apps is disabled. Both best-effort / non-fatal.
        try {
            $null = Grant-CippAppGraphConsent -AppId $AppId -Scopes @('openid', 'profile', 'offline_access')
        } catch {
            Write-LogMessage -headers $Headers -API 'ExecApiClient' -message "Failed to admin-consent Graph openid/profile/offline_access for MCP client ${AppId}: $($_.Exception.Message)" -Sev 'Warning'
        }
        try {
            if ($ScopeId -and $ResourceObjectId) { $null = Set-CippMcpResourcePreAuth -ResourceObjectId $ResourceObjectId -ClientAppId $AppId -ScopeId $ScopeId }
        } catch {
            Write-LogMessage -headers $Headers -API 'ExecApiClient' -message "Failed to pre-authorize MCP client $AppId on the CIPP-MCP resource user_impersonation scope: $($_.Exception.Message)" -Sev 'Warning'
        }

        return @{ Success = $true; ClientAppId = $AppId; ResourceAppId = $ResourceAppId; RedirectUris = @($PublicRedirectUris) }
    }
}
