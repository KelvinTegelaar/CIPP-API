function Set-CippMcpResourcePreAuth {
    <#
    .SYNOPSIS
        Pre-authorizes an MCP client app on the CIPP-MCP resource's user_impersonation scope.
    .DESCRIPTION
        Adds the client's appId to the CIPP-MCP resource app's api.preAuthorizedApplications
        (additive, idempotent). Pre-authorization is what makes the client -> resource
        user_impersonation grant require NO consent at all: the resource app trusts the listed
        client, so Entra issues the token without a user or admin consent prompt - which is the
        only reliable path in tenants that disable user consent to applications (CIPP's own
        OauthConsentLowSec standard recommends exactly that).

        This is preferred over an AllPrincipals oauth2PermissionGrant for the resource scope because
        it is written with Application.ReadWrite.All (patching CIPP's own app registration), so it
        does not depend on Directory.ReadWrite.All being consented, nor on the resource service
        principal having replicated - both of which make a create-time consent grant racy.

        Graph delegated scopes (openid/profile/offline_access) cannot be pre-authorized this way and
        still need Grant-CippAppGraphConsent.
    .PARAMETER ResourceObjectId
        Object ID of the CIPP-MCP resource app registration to patch.
    .PARAMETER ClientAppId
        Application (client) ID of the MCP client to pre-authorize.
    .PARAMETER ScopeId
        The id of the resource's user_impersonation oauth2PermissionScope.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$ResourceObjectId,
        [Parameter(Mandatory)][string]$ClientAppId,
        [Parameter(Mandatory)][string]$ScopeId
    )

    $ResApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications/$ResourceObjectId`?`$select=api" -NoAuthCheck $true -asapp $true
    $ApiObj = if ($ResApp.api) { $ResApp.api | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable } else { @{} }

    $PreAuth = [System.Collections.Generic.List[object]]::new()
    foreach ($P in @($ApiObj.preAuthorizedApplications)) { $PreAuth.Add($P) }

    $Existing = $PreAuth | Where-Object { $_.appId -eq $ClientAppId } | Select-Object -First 1
    if ($Existing) {
        $Ids = @($Existing.delegatedPermissionIds)
        if ($Ids -contains $ScopeId) { return $false }
        $Existing.delegatedPermissionIds = @($Ids + $ScopeId | Select-Object -Unique)
    } else {
        $PreAuth.Add(@{ appId = $ClientAppId; delegatedPermissionIds = @($ScopeId) })
    }

    $ApiObj.preAuthorizedApplications = @($PreAuth)
    if ($PSCmdlet.ShouldProcess($ClientAppId, 'Pre-authorize MCP client on resource user_impersonation scope')) {
        $Body = @{ api = $ApiObj } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$ResourceObjectId" -type PATCH -body $Body -NoAuthCheck $true -asapp $true
    }
    return $true
}
