function ConvertFrom-CIPPCredentialAuditEvent {
    <#
    .SYNOPSIS
        Turns directory audit events into one row per credential (secret or certificate) they added or removed.
    .DESCRIPTION
        Reads the KeyDescription property an app registration or service principal credential change records,
        and returns the keys present after the change but not before it (action 'Added') and those present before
        but not after (action 'Removed'), with the object and who changed it: a user or an app. Events without a
        KeyDescription change return nothing.
    .PARAMETER Events
        Directory audit events (auditLogs/directoryAudits) with initiatedBy and targetResources.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Events
    )

    $KeyDescriptionRegex = [regex]'\[KeyIdentifier=(?<Id>[^,\]]*),KeyType=(?<Type>[^,\]]*),KeyUsage=(?<Usage>[^,\]]*)'
    $Rows = [System.Collections.Generic.List[object]]::new()
    foreach ($Event in $Events) {
        $App = $Event.initiatedBy.app
        $User = $Event.initiatedBy.user
        $ActorType = if ($User.id -or $User.userPrincipalName) { 'User' } elseif ($App.appId -or $App.servicePrincipalId) { 'Application' } else { 'Unknown' }
        foreach ($Target in $Event.targetResources) {
            foreach ($Prop in $Target.modifiedProperties) {
                if ($Prop.displayName -ne 'KeyDescription') { continue }
                $Old = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Match in $KeyDescriptionRegex.Matches([string]$Prop.oldValue)) { if ($Match.Groups['Id'].Value) { $Old[$Match.Groups['Id'].Value] = $Match } }
                $New = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Match in $KeyDescriptionRegex.Matches([string]$Prop.newValue)) { if ($Match.Groups['Id'].Value) { $New[$Match.Groups['Id'].Value] = $Match } }
                $Changes = @(
                    foreach ($KeyId in $New.Keys) { if (-not $Old.ContainsKey($KeyId)) { @{ Action = 'Added'; KeyId = $KeyId; Match = $New[$KeyId] } } }
                    foreach ($KeyId in $Old.Keys) { if (-not $New.ContainsKey($KeyId)) { @{ Action = 'Removed'; KeyId = $KeyId; Match = $Old[$KeyId] } } }
                )
                foreach ($Change in $Changes) {
                    $KeyId = $Change.KeyId
                    $Match = $Change.Match
                    $Rows.Add([PSCustomObject]@{
                            id                            = if ($Change.Action -eq 'Added') { "$($Target.id)-$KeyId" } else { "$($Target.id)-$KeyId-Removed" }
                            action                        = $Change.Action
                            activityDateTime              = $Event.activityDateTime
                            activityDisplayName           = $Event.activityDisplayName
                            targetId                      = [string]$Target.id
                            targetType                    = [string]$Target.type
                            targetDisplayName             = [string]$Target.displayName
                            keyId                         = $KeyId
                            keyType                       = $Match.Groups['Type'].Value
                            keyUsage                      = $Match.Groups['Usage'].Value
                            initiatedByType               = $ActorType
                            initiatedByName               = [string]($User.userPrincipalName ?? $App.displayName ?? $App.appId)
                            initiatedByAppId              = [string]$App.appId
                            initiatedByServicePrincipalId = [string]$App.servicePrincipalId
                        })
                }
            }
        }
    }
    return $Rows.ToArray()
}
