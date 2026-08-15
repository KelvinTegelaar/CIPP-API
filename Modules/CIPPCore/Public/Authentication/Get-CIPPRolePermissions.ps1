function Get-CIPPRolePermissions {
    <#
    .SYNOPSIS
        Get the permissions associated with a role.
    .DESCRIPTION
        Roles are canonically defined by PermissionRules ({Include, Exclude} -like glob
        arrays, same semantics as base roles in cipp-roles.json: exclude wins). Rules are
        expanded against the live permission universe at read time, so wildcard roles
        automatically cover endpoints added in later releases. Rows saved before the rules
        format get behavior-preserving concrete-string rules synthesized in memory; the
        roles list endpoint persists the migration.
    .PARAMETER RoleName
        The role to get the permissions for.
    .EXAMPLE
        Get-CIPPRolePermissions -RoleName 'mycustomrole'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RoleName
    )

    $Table = Get-CippTable -tablename 'CustomRoles'
    $Filter = "RowKey eq '$RoleName'"
    $Role = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if ($Role) {
        $Rules = $null
        if ($Role.PSObject.Properties.Name -contains 'PermissionRules' -and ![string]::IsNullOrWhiteSpace($Role.PermissionRules)) {
            try {
                $Rules = $Role.PermissionRules | ConvertFrom-Json
            } catch {
                Write-Warning "Unable to parse permission rules for role '$RoleName': $($_.Exception.Message)"
            }
        }
        if (!$Rules -or @($Rules.Include).Count -eq 0) {
            $Rules = ConvertTo-CippPermissionRules -Permissions $Role.Permissions
        }

        $Permissions = $null
        try {
            $Universe = Get-CippHttpPermissions
            if (@($Universe).Count -gt 0) {
                $Expanded = [System.Collections.Generic.List[string]]::new()
                foreach ($Permission in $Universe) {
                    $Allowed = $false
                    foreach ($Include in $Rules.Include) {
                        if ($Permission -like $Include) { $Allowed = $true; break }
                    }
                    if ($Allowed) {
                        foreach ($Exclude in $Rules.Exclude) {
                            if ($Permission -like $Exclude) { $Allowed = $false; break }
                        }
                    }
                    if ($Allowed) { $Expanded.Add($Permission) }
                }
                $Permissions = $Expanded
            }
        } catch {
            Write-Warning "Unable to expand permission rules for role '$RoleName': $($_.Exception.Message)"
        }
        if ($null -eq $Permissions) {
            # Universe unavailable: fall back to the stored snapshot rather than emptying
            # the role. Never expand wildcards without a universe to bound them.
            $Permissions = if (![string]::IsNullOrWhiteSpace($Role.Permissions)) {
                ($Role.Permissions | ConvertFrom-Json).PSObject.Properties.Value | Where-Object { $_ -notmatch '\.None$' }
            } else {
                @()
            }
        }

        $AllowedTenants = if ($Role.AllowedTenants) { $Role.AllowedTenants | ConvertFrom-Json } else { @() }
        $BlockedTenants = if ($Role.BlockedTenants) { $Role.BlockedTenants | ConvertFrom-Json } else { @() }
        $BlockedEndpoints = if ($Role.BlockedEndpoints) { $Role.BlockedEndpoints | ConvertFrom-Json } else { @() }
        [PSCustomObject]@{
            Role             = $Role.RowKey
            Permissions      = @($Permissions)
            PermissionRules  = $Rules
            AllowedTenants   = @($AllowedTenants)
            BlockedTenants   = @($BlockedTenants)
            BlockedEndpoints = @($BlockedEndpoints)
        }
    } else {
        throw "Role $RoleName not found."
    }
}
