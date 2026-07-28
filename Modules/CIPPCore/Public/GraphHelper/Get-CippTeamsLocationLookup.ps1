function Get-CippTeamsLocationLookup {
    <#
    .SYNOPSIS
        Builds a lookup of Teams emergency LocationId -> displayable label for a tenant.

    .DESCRIPTION
        The Teams telephone-number list only carries LocationId / CivicAddressId GUIDs, which
        are meaningless in a table. This resolves them against Skype.Ncs/locations, falling back
        through description -> place name -> street address -> the id itself, matching the
        fallback the Emergency Location picker uses in the UI.

        Returns an empty hashtable if the lookup fails, so callers degrade to a blank column
        rather than failing the whole number list.

    .PARAMETER TenantFilter
        Target tenant (GUID or default domain).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $TenantFilter
    )

    $Lookup = @{}
    try {
        foreach ($Location in @(New-TeamsRequestV2 -TenantFilter $TenantFilter -Path 'Skype.Ncs/locations')) {
            if (-not $Location.id) { continue }
            $Address = @($Location.houseNumber, $Location.streetName, $Location.cityOrTown) | Where-Object { $_ }
            $Lookup[[string]$Location.id] = if ($Location.description) {
                $Location.description
            } elseif ($Location.location) {
                $Location.location
            } elseif ($Address) {
                $Address -join ' '
            } else {
                $Location.id
            }
        }
    } catch {
        Write-Information "Could not resolve Teams emergency locations for $TenantFilter : $($_.Exception.Message)"
    }
    return $Lookup
}
