function Test-CippAllTenantsBlocked {
    <#
    .SYNOPSIS
        Whether the current caller's roles block the AllTenants pseudo-tenant.

    .DESCRIPTION
        Reads the roles Test-CIPPAccess resolved for this request. Admin and superadmin are never
        blocked; otherwise the caller is blocked only when every custom role sets BlockAllTenants,
        so any unflagged custom role still grants it. A role that fails to load grants nothing.

    .PARAMETER Roles
        Effective role names. Defaults to the roles Test-CIPPAccess recorded for this request.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string[]]$Roles = @($script:CippAccessUserContext.Roles)
    )

    if ($Roles -contains 'admin' -or $Roles -contains 'superadmin') {
        return $false
    }

    $DefaultRoles = @('superadmin', 'admin', 'editor', 'readonly', 'anonymous', 'authenticated')
    $CustomRoles = @($Roles | Where-Object { $_ -and $DefaultRoles -notcontains $_ })
    if ($CustomRoles.Count -eq 0) {
        return $false
    }

    foreach ($CustomRole in $CustomRoles) {
        try {
            if (-not (Get-CippAccessScopeRule -Role $CustomRole).BlockAllTenants) {
                return $false
            }
        } catch {
            Write-Information $_.Exception.Message
        }
    }
    return $true
}
