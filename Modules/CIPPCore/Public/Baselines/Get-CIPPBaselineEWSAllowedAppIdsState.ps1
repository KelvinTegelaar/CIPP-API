function Get-CIPPBaselineEWSAllowedAppIdsState {
    <#
    .SYNOPSIS
        Prepare hook for EWSAllowedAppIds: is EWS enabled with every required app allowed.
    .DESCRIPTION
        Reads the allow list live (it is not part of the cached organization config) and
        grades EwsEnabled, the required app IDs missing from the list, and known-malicious
        app IDs on it. Extra IDs on the list are never drift.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $StateParams = @{
        TenantFilter             = $TenantFilter
        Presets                  = $Item.Variables.presets
        CustomAppIds             = $Item.Variables.customAppIds
        IncludeEwsPermissionApps = [bool]$Item.Variables.includeEwsPermissionApps
        IncludeHybridApp         = $Item.Variables.includeHybridApp -ne $false
        RemoveMaliciousApps      = [bool]$Item.Variables.removeMaliciousApps
        LogApi                   = 'Baselines'
    }
    $State = Get-CIPPEwsAllowedAppIdState @StateParams

    $Current = [PSCustomObject]@{
        ewsEnabled             = $State.EwsEnabled -eq $true
        missingAppIds          = @($State.MissingAppIds)
        maliciousAppIdsPresent = @($State.MaliciousAppIdsPresent)
    }
    # Carried for the executor, which re-reads the list live before writing.
    $Current | Add-Member -NotePropertyName 'stateParams' -NotePropertyValue $StateParams

    @{
        Expected = [PSCustomObject]@{ ewsEnabled = $true; missingAppIds = @(); maliciousAppIdsPresent = @() }
        Current  = $Current
    }
}
