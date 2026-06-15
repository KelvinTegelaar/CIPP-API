function Set-CIPPMCPClientApp {
    <#
    .SYNOPSIS
        Configures an API client's app registration to act as the MCP OAuth resource.
    .DESCRIPTION
Sets a cipp API client.
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

    $PatchBody = @{
        identifierUris = @($IdentifierUris)
        api            = $Api
    } | ConvertTo-Json -Depth 10 -Compress

    if ($PSCmdlet.ShouldProcess($AppId, 'Configure app registration for MCP')) {
        try {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($App.id)" -type PATCH -body $PatchBody -NoAuthCheck $true -asapp $true
            Write-LogMessage -headers $Headers -API 'ExecApiClient' -message "Configured app registration $AppId as MCP resource (identifier URIs + v2 tokens)." -Sev 'Info'
            return @{ Success = $true; IdentifierUris = @($IdentifierUris) }
        } catch {
            $ErrMsg = $_.Exception.Message
            if ($ErrMsg -match 'identifierUri' -or $ErrMsg -match 'already exists' -or $ErrMsg -match 'in use') {
                throw "The MCP resource URIs are already assigned to another application. Only one API client can be the MCP resource client. ($ErrMsg)"
            }
            throw
        }
    }
}
