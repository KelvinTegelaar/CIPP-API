function Grant-CippAppGraphConsent {
    <#
    .SYNOPSIS
        Ensures a tenant-wide (AllPrincipals) oauth2PermissionGrant exists from an app's service
        principal to a resource API (Microsoft Graph by default), covering the given delegated scopes.
    .DESCRIPTION
        Admin-consents delegated Microsoft Graph scopes for an app registration in the partner
        tenant, so users signing in through it are not prompted to consent. Used to pre-consent
        the OIDC + offline_access scopes an MCP client (Copilot Studio, Claude, ChatGPT, VS Code)
        requests: without offline_access consent, Entra will not issue a refresh token and the
        client re-authenticates every time the access token expires (~hourly).

        This matters most in tenants that disable user consent to applications (which CIPP's own
        OauthConsentLowSec standard recommends): there, an un-consented offline_access request
        silently yields no refresh token. Admin consent is the only reliable path.

        Additive — existing consented scopes are preserved and only the missing ones are added.
        The service principal of a freshly created app is not always queryable immediately, so
        the client SP lookup retries briefly before giving up.
    .PARAMETER AppId
        Application (client) ID of the app whose service principal should receive the grant.
    .PARAMETER Scopes
        Delegated scope names to ensure are consented (e.g. openid, profile, offline_access for
        Graph, or user_impersonation for a custom resource).
    .PARAMETER ResourceAppId
        Application (client) ID of the resource whose delegated scopes are being consented. Defaults
        to Microsoft Graph. Pass a custom API's app id to admin-consent, for example, an MCP public
        client (SSO app) on the MCP resource app's user_impersonation scope.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string[]]$Scopes,

        [Parameter()]
        [string]$ResourceAppId = '00000003-0000-0000-c000-000000000000'
    )

    # The app's own service principal may still be replicating right after creation.
    $ClientSp = $null
    for ($Attempt = 1; $Attempt -le 3 -and -not $ClientSp.id; $Attempt++) {
        try {
            $ClientSp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$AppId')?`$select=id" -NoAuthCheck $true -asapp $true
        } catch {
            Write-Information "[App-Consent] Service principal for $AppId not queryable yet (attempt $Attempt): $($_.Exception.Message)"
        }
        if (-not $ClientSp.id -and $Attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    if (-not $ClientSp.id) {
        throw "Service principal for app '$AppId' was not found; cannot write consent grant yet."
    }

    # The resource's service principal may also still be replicating - e.g. right after the dedicated
    # CIPP-MCP resource app is created, this consent runs in the same flow. Retry before giving up.
    $ResourceSp = $null
    for ($Attempt = 1; $Attempt -le 3 -and -not $ResourceSp.id; $Attempt++) {
        try {
            $ResourceSp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$ResourceAppId')?`$select=id" -NoAuthCheck $true -asapp $true
        } catch {
            Write-Information "[App-Consent] Resource service principal for $ResourceAppId not queryable yet (attempt $Attempt): $($_.Exception.Message)"
        }
        if (-not $ResourceSp.id -and $Attempt -lt 3) { Start-Sleep -Seconds 2 }
    }
    if (-not $ResourceSp.id) {
        throw "Resource service principal for app '$ResourceAppId' was not found in this tenant."
    }

    $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ClientSp.id)/oauth2PermissionGrants" -NoAuthCheck $true -asapp $true)
    $TenantGrant = $Grants | Where-Object { $_.resourceId -eq $ResourceSp.id -and $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1

    if ($TenantGrant) {
        $CurrentScopes = @($TenantGrant.scope -split ' ' | Where-Object { $_ })
        $MissingScopes = @($Scopes | Where-Object { $_ -notin $CurrentScopes })
        if ($MissingScopes.Count -eq 0) {
            return [PSCustomObject]@{ AppId = $AppId; Action = 'nochange'; Scopes = $CurrentScopes }
        }
        $MergedScopes = (@($CurrentScopes + $MissingScopes) | Sort-Object -Unique) -join ' '
        $PatchBody = @{ scope = $MergedScopes } | ConvertTo-Json -Compress
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($TenantGrant.id)" -body $PatchBody -type PATCH -NoAuthCheck $true -asapp $true
        return [PSCustomObject]@{ AppId = $AppId; Action = 'updated'; Scopes = @($MergedScopes -split ' ') }
    }

    $CreateBody = @{
        clientId    = $ClientSp.id
        consentType = 'AllPrincipals'
        resourceId  = $ResourceSp.id
        scope       = ($Scopes -join ' ')
    } | ConvertTo-Json -Compress
    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -body $CreateBody -type POST -NoAuthCheck $true -asapp $true
    return [PSCustomObject]@{ AppId = $AppId; Action = 'created'; Scopes = @($Scopes) }
}
