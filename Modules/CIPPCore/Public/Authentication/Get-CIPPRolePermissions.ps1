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
        $Permissions = $Role.Permissions | ConvertFrom-Json
        [PSCustomObject]@{
            Role           = $Role.RowKey
            Permissions    = $Permissions.PSObject.Properties.Value
            AllowedTenants = if ($Role.AllowedTenants) { $Role.AllowedTenants | ConvertFrom-Json } else { @() }
            BlockedTenants = if ($Role.BlockedTenants) { $Role.BlockedTenants | ConvertFrom-Json } else { @() }
        }
    } else {
        throw "Role $RoleName not found."
    }
}