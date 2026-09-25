function Get-CIPPCAAppDisplayName {
    <#
    .SYNOPSIS
        Resolves an application ID referenced by a Conditional Access policy to a readable name.
    .DESCRIPTION
        Looks the ID up, in order, in the curated app descriptions, the tenant's cached service principals,
        the known bypass-app list, the FOCI family list, the well-known app list, the Microsoft first-party
        name table and the built-in application-group aliases (Office365, MicrosoftAdminPortals).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppId,
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Key = $AppId.ToLowerInvariant()
    $Data = $Context.Data

    $Description = $Data.AppDescriptionById[$Key]
    if ($Description.displayName) { return "$($Description.displayName)" }

    $ServicePrincipal = $Context.ServicePrincipals[$Key]
    if ($ServicePrincipal.displayName) { return "$($ServicePrincipal.displayName)" }

    $Bypass = $Data.BypassAppById[$Key]
    if ($Bypass.displayName) { return "$($Bypass.displayName)" }

    $Foci = $Data.FociById[$Key]
    if ($Foci.displayName) { return "$($Foci.displayName)" }

    $WellKnown = $Data.WellKnownById[$Key]
    if ($WellKnown.displayName) { return "$($WellKnown.displayName)" }

    $FirstParty = $Data.FirstPartyNames[$Key]
    if ($FirstParty) { return "$FirstParty" }

    $Alias = $Data.AppGroupAliases[$Key]
    if ($Alias.displayName) { return "$($Alias.displayName)" }

    return $AppId
}
