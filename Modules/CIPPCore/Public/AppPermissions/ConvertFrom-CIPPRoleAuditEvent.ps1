function ConvertFrom-CIPPRoleAuditEvent {
    <#
    .SYNOPSIS
        Turns directory audit events into one row per directory role assigned to a service principal.
    .DESCRIPTION
        Reads 'Add member to role' events (direct and through PIM) and 'Add member to group' events whose target is
        a service principal, and returns the service principal, the role (template id and name) or the group it was
        added to, and who did it: a user or an app. Other events, eligible assignments and changes to users return
        nothing. Whether a group holds a role is up to the caller.
    .PARAMETER Events
        Directory audit events (auditLogs/directoryAudits) with initiatedBy and targetResources.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Events
    )

    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Event in $Events) {
        $Activity = [string]$Event.activityDisplayName
        $IsRole = $Activity.StartsWith('Add member to role', [System.StringComparison]::OrdinalIgnoreCase)
        $IsGroup = $Activity -eq 'Add member to group'
        if (-not $IsRole -and -not $IsGroup) { continue }
        $SpTarget = $null
        $RoleId = $null
        $RoleName = $null
        $GroupId = $null
        $GroupName = $null
        foreach ($Target in $Event.targetResources) {
            if ($Target.type -eq 'ServicePrincipal' -and -not $SpTarget) { $SpTarget = $Target }
            if ($Target.type -eq 'Role') {
                if (-not $RoleId) { $RoleId = [string]$Target.id }
                if (-not $RoleName) { $RoleName = [string]$Target.displayName }
            }
            if ($Target.type -eq 'Group') {
                if (-not $GroupId) { $GroupId = [string]$Target.id }
                if (-not $GroupName) { $GroupName = [string]$Target.displayName }
            }
            foreach ($Prop in $Target.modifiedProperties) {
                $Value = ([string]$Prop.newValue).Trim('"', ' ')
                if (-not $Value) { continue }
                switch ($Prop.displayName) {
                    'Role.TemplateId' { $RoleId = $Value }
                    'Role.DisplayName' { $RoleName = $Value }
                    'Group.ObjectID' { $GroupId = $Value }
                    'Group.DisplayName' { $GroupName = $Value }
                }
            }
        }
        if (-not $SpTarget.id -or ($IsRole -and -not $RoleId) -or ($IsGroup -and -not $GroupId)) { continue }
        $App = $Event.initiatedBy.app
        $User = $Event.initiatedBy.user
        $ActorType = if ($User.id -or $User.userPrincipalName) { 'User' } elseif ($App.appId -or $App.servicePrincipalId) { 'Application' } else { 'Unknown' }
        $Rows.Add([PSCustomObject]@{
                id                            = "$($SpTarget.id)-$(if ($IsRole) { $RoleId } else { $GroupId })-$($Event.id ?? $Event.activityDateTime)"
                activityDateTime              = $Event.activityDateTime
                activityDisplayName           = $Event.activityDisplayName
                targetId                      = [string]$SpTarget.id
                targetDisplayName             = [string]$SpTarget.displayName
                roleId                        = if ($IsRole) { $RoleId } else { $null }
                roleName                      = if ($IsRole) { $RoleName } else { $null }
                groupId                       = if ($IsGroup) { $GroupId } else { $null }
                groupName                     = if ($IsGroup) { $GroupName } else { $null }
                initiatedByType               = $ActorType
                initiatedByName               = [string]($User.userPrincipalName ?? $App.displayName ?? $App.appId)
                initiatedByAppId              = [string]$App.appId
                initiatedByServicePrincipalId = [string]$App.servicePrincipalId
            })
    }
    return $Rows.ToArray()
}
