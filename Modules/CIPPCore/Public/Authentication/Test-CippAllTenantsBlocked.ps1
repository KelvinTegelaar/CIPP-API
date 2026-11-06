function Test-CippAllTenantsBlocked {
    <#
    .SYNOPSIS
        Whether the current caller's roles block the AllTenants pseudo-tenant, or with -TenantGroups, tenant groups in the tenant selector.

    .DESCRIPTION
        Reads the roles Test-CIPPAccess resolved for this request. Admin and superadmin are never
        blocked; otherwise the caller is blocked only when every custom role sets the flag (BlockAllTenants or BlockTenantGroups),
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
        [string[]]$Roles = @($script:CippAccessUserContext.Roles),

        [switch]$TenantGroups
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
            $Rule = Get-CippAccessScopeRule -Role $CustomRole
            if (-not $(if ($TenantGroups) { $Rule.BlockTenantGroups } else { $Rule.BlockAllTenants })) {
                return $false
            }
        } catch {
            Write-Information $_.Exception.Message
        }
    }
    return $true
}
