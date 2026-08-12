function Format-CIPPCAPolicy {
    <#
    .SYNOPSIS
        Canonicalizes a conditional access policy body to full desired-state shape for a PATCH.
    .DESCRIPTION
        Deploying a CA template over an existing policy is a PATCH, and PATCH is a merge: anything
        the body leaves out keeps whatever the tenant already had. Editors and older releases
        stripped "empty" keys when saving, so a template that clears an assignment - excludeUsers,
        includeGroups, platforms - could never say so, and the tenant policy never converged.

        This runs at the deploy/edit boundary and makes absence explicit, healing already-stored
        templates without a re-save. Two phases:

        1. Expand - every managed key the body omits is added back as its cleared form: [] for
           assignment collections, null for the condition blocks Graph models as objects. A child
           is only expanded when its parent exists, and clientAppTypes is deliberately skipped -
           Graph requires it non-empty, so absence there stays a merge rather than a broken clear.
           grantControls/sessionControls follow an at-least-one rule: the missing one is added as
           null only while the other has a value, since Graph requires a policy to have one.

        2. Collapse - the handful of condition containers Graph refuses outright when their
           required "include" collection is empty (platforms, locations, devices,
           clientApplications, the guest/external user blocks, grantControls) become $null rather
           than being removed - null is accepted on a create and still clears on an update. Empty
           assignment arrays are deliberately KEPT: an explicit "includeGroups": [] is the only
           thing that strips a group off a policy that already has one.
    .PARAMETER Policy
        The parsed CA policy object. Mutated in place.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Policy
    )

    function Test-CIPPCAHasContent {
        param($Value)
        if ($null -eq $Value) { return $false }
        if ($Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($Value) }
        if ($Value -is [bool]) { return $Value }
        if ($Value -is [Array] -or $Value -is [System.Collections.IList]) {
            foreach ($Item in $Value) {
                if (Test-CIPPCAHasContent -Value $Item) { return $true }
            }
            return $false
        }
        if ($Value -is [PSCustomObject]) {
            foreach ($Property in $Value.PSObject.Properties) {
                # An @odata.type on its own describes an otherwise empty block, it is not content.
                if ($Property.Name -like '*@odata*') { continue }
                if (Test-CIPPCAHasContent -Value $Property.Value) { return $true }
            }
            return $false
        }
        return $true
    }

    function Add-CIPPCAClearedKey {
        param($Parent, [string[]]$Collections, [string[]]$NullBlocks)
        if ($null -eq $Parent -or $Parent -isnot [PSCustomObject]) { return }
        foreach ($Name in $Collections) {
            if ($Parent.PSObject.Properties.Name -notcontains $Name -or $null -eq $Parent.$Name) {
                $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue @() -Force
            } elseif (-not (Test-CIPPCAHasContent -Value $Parent.$Name)) {
                # Whitespace-only entries select nothing; normalise them to a clean clear.
                $Parent.$Name = @()
            }
        }
        foreach ($Name in $NullBlocks) {
            if ($Parent.PSObject.Properties.Name -notcontains $Name) {
                $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue $null -Force
            }
        }
    }

    function Clear-CIPPCAContainer {
        param($Parent, [string]$Name, [string[]]$RequiredAnyOf)
        if ($null -eq $Parent -or $Parent -isnot [PSCustomObject]) { return }
        if ($Parent.PSObject.Properties.Name -notcontains $Name) { return }
        if ($null -eq $Parent.$Name) { return }
        foreach ($Required in $RequiredAnyOf) {
            if (Test-CIPPCAHasContent -Value $Parent.$Name.$Required) { return }
        }
        $Parent.$Name = $null
    }

    # --- Phase 1: expand ------------------------------------------------------------------------
    # conditions / users / applications are required by Graph and never invented or nulled here;
    # their children are only expanded when the parent is actually present.
    $Conditions = $Policy.conditions
    if ($Conditions -is [PSCustomObject]) {
        Add-CIPPCAClearedKey -Parent $Conditions `
            -Collections @('signInRiskLevels', 'userRiskLevels', 'servicePrincipalRiskLevels') `
            -NullBlocks @('platforms', 'locations', 'devices', 'clientApplications', 'authenticationFlows', 'insiderRiskLevels')
        Add-CIPPCAClearedKey -Parent $Conditions.users `
            -Collections @('includeUsers', 'excludeUsers', 'includeGroups', 'excludeGroups', 'includeRoles', 'excludeRoles') `
            -NullBlocks @('includeGuestsOrExternalUsers', 'excludeGuestsOrExternalUsers')
        Add-CIPPCAClearedKey -Parent $Conditions.applications `
            -Collections @('includeApplications', 'excludeApplications', 'includeUserActions', 'includeAuthenticationContextClassReferences') `
            -NullBlocks @('applicationFilter')
        Add-CIPPCAClearedKey -Parent $Conditions.devices -Collections @() -NullBlocks @('deviceFilter')
        Add-CIPPCAClearedKey -Parent $Conditions.clientApplications -Collections @() -NullBlocks @('servicePrincipalFilter')
    }
    # A policy must carry grantControls or sessionControls - say the missing one's absence out
    # loud (as null) only while the other still has a value, and never null both.
    foreach ($Control in 'grantControls', 'sessionControls') {
        if ($Policy.PSObject.Properties.Name -contains $Control) { continue }
        $Other = if ($Control -eq 'grantControls') { 'sessionControls' } else { 'grantControls' }
        if ($Policy.PSObject.Properties.Name -contains $Other -and $null -ne $Policy.$Other) {
            $Policy | Add-Member -NotePropertyName $Control -NotePropertyValue $null -Force
        }
    }

    # --- Phase 2: collapse ----------------------------------------------------------------------
    # Filters first: a filter carrying a mode but no rule selects nothing and Graph rejects it, and
    # clearing it before the parent lets an otherwise-empty devices/clientApplications block collapse
    # too rather than surviving on the strength of a filter that does nothing.
    Clear-CIPPCAContainer -Parent $Policy.conditions.applications -Name 'applicationFilter' -RequiredAnyOf 'rule'
    Clear-CIPPCAContainer -Parent $Policy.conditions.devices -Name 'deviceFilter' -RequiredAnyOf 'rule'
    Clear-CIPPCAContainer -Parent $Policy.conditions.clientApplications -Name 'servicePrincipalFilter' -RequiredAnyOf 'rule'

    Clear-CIPPCAContainer -Parent $Policy.conditions -Name 'platforms' -RequiredAnyOf 'includePlatforms'
    Clear-CIPPCAContainer -Parent $Policy.conditions -Name 'locations' -RequiredAnyOf 'includeLocations'
    Clear-CIPPCAContainer -Parent $Policy.conditions -Name 'devices' -RequiredAnyOf 'deviceFilter', 'includeDevices'
    Clear-CIPPCAContainer -Parent $Policy.conditions -Name 'clientApplications' -RequiredAnyOf 'includeServicePrincipals'
    Clear-CIPPCAContainer -Parent $Policy.conditions.users -Name 'includeGuestsOrExternalUsers' -RequiredAnyOf 'guestOrExternalUserTypes'
    Clear-CIPPCAContainer -Parent $Policy.conditions.users -Name 'excludeGuestsOrExternalUsers' -RequiredAnyOf 'guestOrExternalUserTypes'
    Clear-CIPPCAContainer -Parent $Policy -Name 'grantControls' -RequiredAnyOf 'builtInControls', 'customAuthenticationFactors', 'termsOfUse', 'authenticationStrength'

    # sessionControls carries no required member, so it only has to survive as *something*
    # addressable - an empty object would be dropped from the body by ConvertTo-Json's caller.
    if ($Policy.PSObject.Properties.Name -contains 'sessionControls' -and $null -ne $Policy.sessionControls) {
        if (@($Policy.sessionControls.PSObject.Properties).Count -eq 0) {
            $Policy.sessionControls = $null
        }
    }
}
