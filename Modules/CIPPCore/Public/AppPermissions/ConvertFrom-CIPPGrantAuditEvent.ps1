function ConvertFrom-CIPPGrantAuditEvent {
    <#
    .SYNOPSIS
        Turns directory audit events into one row per delegated permission grant they added.
    .DESCRIPTION
        Reads 'Add delegated permission grant' events and returns the client app (ServicePrincipal.ObjectID), the
        resource API the event targets, the consent type and scopes, and who added the grant: a user or an app.
        Other events return nothing.
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
        if (-not ([string]$Event.activityDisplayName).StartsWith('Add delegated permission grant', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        foreach ($Target in $Event.targetResources) {
            if ($Target.type -ne 'ServicePrincipal') { continue }
            $ClientId = $null
            $ConsentType = $null
            $Scope = $null
            foreach ($Prop in $Target.modifiedProperties) {
                $Value = ([string]$Prop.newValue).Trim('"', ' ')
                switch ($Prop.displayName) {
                    'ServicePrincipal.ObjectID' { $ClientId = $Value }
                    'DelegatedPermissionGrant.ConsentType' { $ConsentType = $Value }
                    'DelegatedPermissionGrant.Scope' { $Scope = $Value }
                }
            }
            if (-not $ClientId -or -not $Target.id) { continue }
            $App = $Event.initiatedBy.app
            $User = $Event.initiatedBy.user
            $ActorType = if ($User.id -or $User.userPrincipalName) { 'User' } elseif ($App.appId -or $App.servicePrincipalId) { 'Application' } else { 'Unknown' }
            $Rows.Add([PSCustomObject]@{
                    id                            = "$ClientId-$($Target.id)-$($Event.id ?? $Event.activityDateTime)"
                    activityDateTime              = $Event.activityDateTime
                    activityDisplayName           = $Event.activityDisplayName
                    clientId                      = $ClientId
                    resourceId                    = [string]$Target.id
                    resourceDisplayName           = [string]$Target.displayName
                    consentType                   = $ConsentType
                    scope                         = $Scope
                    initiatedByType               = $ActorType
                    initiatedByName               = [string]($User.userPrincipalName ?? $App.displayName ?? $App.appId)
                    initiatedByAppId              = [string]$App.appId
                    initiatedByServicePrincipalId = [string]$App.servicePrincipalId
                })
            break
        }
    }
    return $Rows.ToArray()
}
