function New-CIPPMcpResourceApp {
    <#
    .SYNOPSIS
        Ensures the dedicated, CIPP-managed CIPP-MCP resource app registration exists.
    .DESCRIPTION
        In the MCP OAuth flow the *resource* app is the token audience and the identity the MCP
        endpoint is exposed as - it holds the host identifier URIs (https://<host> and
        https://<host>/api/ExecMcp), exposes the user_impersonation scope, and is what EasyAuth
        validates incoming tokens against. It is deliberately NOT an OAuth client: it has no redirect
        URIs, no secret and no public-client flow. The apps that AI connectors sign in AS are the
        MCPAllowed API clients (separate app registrations, each with its own role, IP range,
        redirect URIs and Conditional Access) - keeping client and resource separate is what stops
        the non-interactive refresh being "a token for itself" (AADSTS90009) and lets an MSP apply
        device-compliance CA to the client apps without affecting the resource.

        Idempotent and self-healing. It resolves the resource app in this order: the appId stored in
        the CippMcpResource table; an existing CIPP-MCP app that already owns this instance's host
        URI (bind); an existing empty CIPP-MCP app left by a previous failed create (reuse, so we
        don't spawn duplicates); otherwise create one. Before adding the host URIs it makes sure no
        other app holds them: if the holder is one of CIPP's own MCP API clients (a single-app
        leftover) it frees the URIs from it automatically; if it's a foreign app it records the
        conflict (table + logbook) and throws so the pages can flag it. Persists
        appId/objectId/scopeId to the table and returns @{ AppId; ObjectId; ScopeId }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param($Headers)

    $Hostname = $env:WEBSITE_HOSTNAME
    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        throw 'WEBSITE_HOSTNAME is not set; cannot determine the MCP resource URL.'
    }
    $DisplayName = 'CIPP-MCP'
    $McpEndpointUri = "https://$Hostname/api/ExecMcp"
    $HostUris = @("https://$Hostname", $McpEndpointUri)
    $Table = Get-CippTable -tablename 'CippMcpResource'

    # 1) Stored appId is authoritative.
    $Stored = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'McpResource' and RowKey eq 'McpResource'"
    $App = $null
    if ($Stored.AppId) {
        try {
            $App = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($Stored.AppId)')" -NoAuthCheck $true -AsApp $true
        } catch {
            Write-Information "[MCP-Resource] Stored CIPP-MCP appId $($Stored.AppId) no longer resolves; will rediscover/recreate. $($_.Exception.Message)"
        }
    }

    # 2) Bind to an existing CIPP-MCP app that owns the host URI; else reuse an empty CIPP-MCP app
    #    left behind by a previous failed create (avoids spawning duplicates). Simple displayName
    #    filter (no advanced-query quirks), matched in PowerShell.
    if (-not $App.id) {
        $Candidates = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$DisplayName'&`$select=id,appId,api,identifierUris" -NoAuthCheck $true -AsApp $true)
        $App = $Candidates | Where-Object { @($_.identifierUris) -contains $McpEndpointUri } | Select-Object -First 1
        if (-not $App.id) {
            $App = $Candidates | Where-Object { @($_.identifierUris).Count -eq 0 } | Select-Object -First 1
            if ($App.id) { Write-Information "[MCP-Resource] Reusing existing empty CIPP-MCP app ($($App.appId)) instead of creating a new one." }
        }
    }

    # 3) Before creating/claiming, make sure no OTHER app holds a host URI (checked here so a foreign
    #    conflict never leaves an orphan created behind it). Self-heal our own MCP API clients
    #    (single-app leftovers); record + warn on a foreign app. Skip URIs this app already owns.
    foreach ($HostUri in $HostUris) {
        if ($App -and (@($App.identifierUris) -contains $HostUri)) { continue }
        $Holder = $null
        try {
            $Holders = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=identifierUris/any(u:u eq '$HostUri')&`$count=true&`$select=id,appId,displayName" -NoAuthCheck $true -AsApp $true -ComplexFilter)
            $Holder = $Holders | Where-Object { $_.appId -and $_.appId -ne $App.appId } | Select-Object -First 1
        } catch {
            Write-Information "[MCP-Resource] Could not check for a host-URI holder ($HostUri): $($_.Exception.Message)"
        }
        if (-not $Holder) { continue }

        $OwnedClient = $null
        try {
            $ApiClientsTable = Get-CippTable -tablename 'ApiClients'
            $OwnedClient = Get-CIPPAzDataTableEntity @ApiClientsTable -Filter "RowKey eq '$($Holder.appId)'"
        } catch {
            Write-Information "[MCP-Resource] Could not check whether $($Holder.appId) is a managed API client: $($_.Exception.Message)"
        }
        if ($OwnedClient.RowKey) {
            $HolderApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($Holder.appId)')?`$select=id,identifierUris" -NoAuthCheck $true -AsApp $true
            $Kept = @(@($HolderApp.identifierUris) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $HostUris -notcontains $_ })
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($HolderApp.id)" -type PATCH -body (@{ identifierUris = @($Kept) } | ConvertTo-Json -Compress) -NoAuthCheck $true -asapp $true
            Write-LogMessage -headers $Headers -API 'McpResource' -message "Migrated MCP: freed the resource URI ($HostUri) from API client '$($Holder.displayName)' ($($Holder.appId)) so the dedicated CIPP-MCP resource app can own it." -Sev 'Info'
        } else {
            $ConflictMsg = "MCP setup blocked: the app registration '$($Holder.displayName)' ($($Holder.appId)) already uses the MCP resource URL ($HostUri) and is not a CIPP-managed API client. Delete that app registration in Entra, then run Save to Azure again."
            Write-LogMessage -headers $Headers -API 'McpResource' -message $ConflictMsg -Sev 'Warning'
            $null = Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey    = 'McpResource'
                RowKey          = 'Error'
                Message         = $ConflictMsg
                ConflictAppId   = "$($Holder.appId)"
                ConflictAppName = "$($Holder.displayName)"
                DetectedAt      = (Get-Date).ToUniversalTime().ToString('o')
            } -Force
            throw $ConflictMsg
        }
    }

    # 4) Create only if nothing could be resolved or reused.
    if (-not $App.id) {
        $CreateBody = @{
            displayName    = $DisplayName
            signInAudience = 'AzureADMyOrg'
            api            = @{
                requestedAccessTokenVersion = 2
                oauth2PermissionScopes      = @(
                    @{
                        adminConsentDescription = 'Allow the application to access CIPP-API on behalf of the signed-in user.'
                        adminConsentDisplayName = 'Access CIPP-API'
                        id                      = [guid]::NewGuid().ToString()
                        isEnabled               = $true
                        type                    = 'User'
                        userConsentDescription  = 'Allow the application to access CIPP-API on your behalf.'
                        userConsentDisplayName  = 'Access CIPP-API'
                        value                   = 'user_impersonation'
                    }
                )
            }
        } | ConvertTo-Json -Depth 10 -Compress
        if ($PSCmdlet.ShouldProcess($DisplayName, 'Create MCP resource app')) {
            $App = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/applications' -type POST -body $CreateBody -NoAuthCheck $true -asapp $true
            Write-LogMessage -headers $Headers -API 'McpResource' -message "Created MCP resource app '$DisplayName' ($($App.appId))." -Sev 'Info'
        }
    }
    if (-not $App.appId) {
        throw 'MCP resource app could not be created or resolved.'
    }

    # Desired scope + identifier URIs.
    $ApiObj = if ($App.api) { $App.api | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable } else { @{} }
    $ScopeChanged = $false
    $Scopes = [System.Collections.Generic.List[object]]::new()
    if ($ApiObj.oauth2PermissionScopes) { foreach ($S in $ApiObj.oauth2PermissionScopes) { $Scopes.Add($S) } }
    $UserImpersonation = $Scopes | Where-Object { $_.value -eq 'user_impersonation' } | Select-Object -First 1
    if (-not $UserImpersonation) {
        $UserImpersonation = @{
            adminConsentDescription = 'Allow the application to access CIPP-API on behalf of the signed-in user.'
            adminConsentDisplayName = 'Access CIPP-API'
            id                      = [guid]::NewGuid().ToString()
            isEnabled               = $true
            type                    = 'User'
            userConsentDescription  = 'Allow the application to access CIPP-API on your behalf.'
            userConsentDisplayName  = 'Access CIPP-API'
            value                   = 'user_impersonation'
        }
        $Scopes.Add($UserImpersonation)
        $ScopeChanged = $true
    }
    $ScopeId = $UserImpersonation.id
    $VersionChanged = ($ApiObj.requestedAccessTokenVersion -ne 2)

    $IdentifierUris = [System.Collections.Generic.List[string]]::new()
    foreach ($Uri in @($App.identifierUris)) { if (-not [string]::IsNullOrWhiteSpace($Uri) -and $IdentifierUris -notcontains $Uri) { $IdentifierUris.Add($Uri) } }
    $UriChanged = $false
    foreach ($Uri in (@("api://$($App.appId)") + $HostUris)) { if ($IdentifierUris -notcontains $Uri) { $IdentifierUris.Add($Uri); $UriChanged = $true } }

    # 5) Reconcile the resource app (identifier URIs + v2 tokens + user_impersonation). Retry the
    #    "in use" case briefly - right after freeing a URI, Entra can take a few seconds to release it.
    if ($ScopeChanged -or $VersionChanged -or $UriChanged) {
        if ($PSCmdlet.ShouldProcess($DisplayName, 'Reconcile MCP resource app')) {
            $ApiObj.requestedAccessTokenVersion = 2
            $ApiObj.oauth2PermissionScopes = @($Scopes)
            $PatchBody = @{ identifierUris = @($IdentifierUris); api = $ApiObj } | ConvertTo-Json -Depth 10 -Compress
            for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
                try {
                    $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($App.id)" -type PATCH -body $PatchBody -NoAuthCheck $true -asapp $true
                    Write-LogMessage -headers $Headers -API 'McpResource' -message "Reconciled MCP resource app '$DisplayName' ($($App.appId)): identifier URIs, v2 tokens, user_impersonation." -Sev 'Info'
                    break
                } catch {
                    $ErrMsg = $_.Exception.Message
                    $InUse = $ErrMsg -match 'identifierUri' -or $ErrMsg -match 'already exists' -or $ErrMsg -match 'in use'
                    if ($InUse -and $Attempt -lt 5) { Start-Sleep -Seconds 3; continue }
                    if ($InUse) {
                        throw "The MCP resource host URIs (https://$Hostname ...) are still assigned to another app registration. If a non-CIPP app holds them, remove it in Entra, then run Save to Azure again. ($ErrMsg)"
                    }
                    throw
                }
            }
        }
    }

    # Ensure a service principal so tokens are issued for this resource.
    $Sp = $null
    for ($Attempt = 1; $Attempt -le 6 -and -not $Sp.id; $Attempt++) {
        try {
            $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$($App.appId)')?`$select=id" -NoAuthCheck $true -AsApp $true
        } catch { $Sp = $null }
        if (-not $Sp.id) {
            if ($Attempt -eq 1) {
                try {
                    $SpBody = @{ accountEnabled = $true; appId = $App.appId; displayName = $DisplayName; tags = @('WindowsAzureActiveDirectoryIntegratedApp') } | ConvertTo-Json -Compress
                    $Sp = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -type POST -body $SpBody -NoAuthCheck $true -asapp $true
                } catch { Write-Information "[MCP-Resource] Service principal create attempt failed: $($_.Exception.Message)" }
            }
            if (-not $Sp.id -and $Attempt -lt 6) { Start-Sleep -Seconds 3 }
        }
    }

    $null = Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = 'McpResource'
        RowKey       = 'McpResource'
        AppId        = "$($App.appId)"
        ObjectId     = "$($App.id)"
        ScopeId      = "$ScopeId"
    } -Force

    # The resource app is wired up, so clear any stored conflict error.
    try {
        $ErrRow = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'McpResource' and RowKey eq 'Error'"
        if ($ErrRow.RowKey) { $null = Remove-CIPPAzDataTableEntity @Table -Entity $ErrRow -Force }
    } catch {
        Write-Information "[MCP-Resource] Could not clear stored MCP conflict error: $($_.Exception.Message)"
    }

    return @{ AppId = "$($App.appId)"; ObjectId = "$($App.id)"; ScopeId = "$ScopeId" }
}
