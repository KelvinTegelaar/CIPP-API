function Get-CippRequestAllowedPermissions {
    <#
    .SYNOPSIS
        Returns the current caller's allowed permissions, resolved once per request.
    .DESCRIPTION
        Built from the roles Test-CIPPAccess resolved for this request - the signed-in user's roles,
        or an API client's role on the client-credentials path - with the same
        Get-CippAllowedPermissions computation /api/me uses. The result is kept in the request
        context slot reset by Initialize-CippRequestContext, so later calls in the same request reuse
        it and nothing carries over to the next request on the worker.

        Returns $null outside an authenticated request (no access context), and an empty list when
        the caller's roles grant nothing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if ($script:CippAllowedPermissionsStorage -and $null -ne $script:CippAllowedPermissionsStorage.Value) {
        return , $script:CippAllowedPermissionsStorage.Value
    }
    if (-not $script:CippAccessUserContext) { return $null }

    $Roles = @($script:CippAccessUserContext.Roles | Where-Object { $_ })
    $Permissions = @(if ($Roles.Count -gt 0) { Get-CippAllowedPermissions -UserRoles $Roles })
    if ($script:CippAllowedPermissionsStorage) { $script:CippAllowedPermissionsStorage.Value = $Permissions }
    return , $Permissions
}
