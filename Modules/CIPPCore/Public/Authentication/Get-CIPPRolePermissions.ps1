function Get-CIPPRolePermissions {
    <#
    .SYNOPSIS
        Get the permissions associated with a role.
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
        $Permissions = ($Role.Permissions | ConvertFrom-Json).PSObject.Properties.Value
        # Stored permissions can reference endpoints removed or renamed in later CIPP
        # versions; drop those so stale entries don't inflate the role's permission set
        # (e.g. failing the Test-CippApiClientRoleGrant subset check). Skip filtering if
        # the valid-permission universe can't be resolved, rather than emptying the role.
        try {
            $ValidPermissions = Get-CippHttpPermissions
            if (@($ValidPermissions).Count -gt 0) {
                $Permissions = @($Permissions | Where-Object { $ValidPermissions -contains $_ })
            }
        } catch {
            Write-Warning "Unable to resolve valid permissions to filter role '$RoleName': $($_.Exception.Message)"
        }
        $AllowedTenants = if ($Role.AllowedTenants) { $Role.AllowedTenants | ConvertFrom-Json } else { @() }
        $BlockedTenants = if ($Role.BlockedTenants) { $Role.BlockedTenants | ConvertFrom-Json } else { @() }
        $BlockedEndpoints = if ($Role.BlockedEndpoints) { $Role.BlockedEndpoints | ConvertFrom-Json } else { @() }
        [PSCustomObject]@{
            Role             = $Role.RowKey
            Permissions      = @($Permissions)
            AllowedTenants   = @($AllowedTenants)
            BlockedTenants   = @($BlockedTenants)
            BlockedEndpoints = @($BlockedEndpoints)
        }
    } else {
        throw "Role $RoleName not found."
    }
}
