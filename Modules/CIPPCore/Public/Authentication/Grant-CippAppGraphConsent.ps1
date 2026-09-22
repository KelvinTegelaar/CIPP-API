function Grant-CippAppGraphConsent {
    <#
    .SYNOPSIS
        Ensures a tenant-wide (AllPrincipals) oauth2PermissionGrant exists from an app's service
        principal to Microsoft Graph, covering the given delegated scopes.
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
        Delegated Microsoft Graph scope names to ensure are consented (e.g. openid, profile,
        offline_access).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string[]]$Scopes
    )

    $GraphAppId = '00000003-0000-0000-c000-000000000000'

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

    $GraphSp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$GraphAppId')?`$select=id" -NoAuthCheck $true -asapp $true
    if (-not $GraphSp.id) {
        throw 'Microsoft Graph service principal was not found in this tenant.'
    }

    $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ClientSp.id)/oauth2PermissionGrants" -NoAuthCheck $true -asapp $true)
    $TenantGrant = $Grants | Where-Object { $_.resourceId -eq $GraphSp.id -and $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1

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
        resourceId  = $GraphSp.id
        scope       = ($Scopes -join ' ')
    } | ConvertTo-Json -Compress
    $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -body $CreateBody -type POST -NoAuthCheck $true -asapp $true
    return [PSCustomObject]@{ AppId = $AppId; Action = 'created'; Scopes = @($Scopes) }
}
