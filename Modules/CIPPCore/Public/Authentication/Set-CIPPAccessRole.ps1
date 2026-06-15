function Set-CIPPAccessRole {
    <#
    .SYNOPSIS
    Set the access role mappings

    .DESCRIPTION
    Set the access role mappings for Entra groups

    .PARAMETER Role
    The role to set (e.g. 'superadmin','admin','editor','readonly','customrole')

    .PARAMETER Group
    The Entra group to set the role for

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Role,
        [Parameter(Mandatory = $true)]
        [string]$Group
    )

    $BlacklistedRoles = @('authenticated', 'anonymous')

    if ($BlacklistedRoles -contains $Role) {
        throw 'Role group cannot be set for authenticated or anonymous roles'
    }

    if (!$Group.id -or !$Group.displayName) {
        throw 'Group is not valid'
    }

    $Role = $Role.ToLower().Trim() -replace ' ', ''

    $Table = Get-CippTable -TableName AccessRoleGroups
    $AccessGroup = Get-CIPPAzDataTableEntity @Table -Filter "RowKey = '$Role'"

    $AccessGroup = [PSCustomObject]@{
        PartitionKey = [string]'AccessRole'
        RowKey       = [string]$Role
        GroupId      = [string]$Group.id
        GroupName    = [string]$Group.displayName
    }

    if ($PSCmdlet.ShouldProcess("Setting access role $Role for group $($Group.displayName)")) {
        Add-CIPPAzDataTableEntity -Table $Table -Entity $AccessGroup -Force
    }
}
