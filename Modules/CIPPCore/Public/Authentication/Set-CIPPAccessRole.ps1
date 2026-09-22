function Set-CIPPAccessRole {
    <#
    .SYNOPSIS
    Set the access role mappings

    .DESCRIPTION
    Set the access role mapping for an Entra group, and apply the change immediately: the
    cached per-user role resolutions are cleared and the allowedUsers projection CRAFT
    authenticates against is refreshed, so nobody waits out the caches.

    .PARAMETER Role
    The role to set (e.g. 'superadmin','admin','editor','readonly','customrole')

    .PARAMETER Group
    The Entra group to map to the role, as an object carrying id and displayName

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Role,
        [Parameter(Mandatory = $true)]
        $Group,
        $Headers,
        $APIName = 'Set-CIPPAccessRole'
    )

    $BlacklistedRoles = @('authenticated', 'anonymous')

    if ($BlacklistedRoles -contains $Role) {
        throw 'Role group cannot be set for authenticated or anonymous roles'
    }

    if (!$Group.id -or !$Group.displayName) {
        throw 'Group is not valid'
    }

    $Role = $Role.ToLower().Trim() -replace ' ', ''

    # PartitionKey must match what Test-CIPPAccessUserRole and Start-UserSyncTimer read.
    $Table = Get-CippTable -TableName AccessRoleGroups
    $AccessGroup = [PSCustomObject]@{
        PartitionKey = [string]'AccessRoleGroups'
        RowKey       = [string]$Role
        GroupId      = [string]$Group.id
        GroupName    = [string]$Group.displayName
    }

    if ($PSCmdlet.ShouldProcess("Setting access role $Role for group $($Group.displayName)")) {
        Add-CIPPAzDataTableEntity @Table -Entity $AccessGroup -Force

        # Group to role mapping decides which roles a user resolves to, so the cached scope rules
        # have to be invalidated with it - and so do the cached per-user resolutions plus the
        # allowedUsers projection CRAFT authenticates against.
        Clear-CippAccessScopeCache
        Clear-CippAccessUserCache
        try { Start-UserSyncTimer } catch {}
        try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Mapped Entra group '$($Group.displayName)' to CIPP access role '$Role'" -Sev 'Info'
    }
}
