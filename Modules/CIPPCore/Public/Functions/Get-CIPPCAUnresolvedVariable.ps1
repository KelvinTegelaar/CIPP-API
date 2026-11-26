function Get-CIPPCAUnresolvedVariable {
    <#
    .SYNOPSIS
        Lists the %variables% a Conditional Access policy still holds after custom variables were applied
    .DESCRIPTION
        Checks the policy's users, locations and applications and the named locations it defines.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Policy)

    @(
        foreach ($List in @($Policy.conditions.users, $Policy.conditions.locations, $Policy.conditions.applications)) {
            if (-not $List) { continue }
            foreach ($Property in $List.PSObject.Properties) {
                foreach ($Value in @($Property.Value)) { if ($Value -is [string] -and $Value -match '^%[^%\s]+%$') { $Value } }
            }
        }
        foreach ($Locations in $Policy.LocationInfo) {
            foreach ($Location in $Locations) {
                foreach ($Value in @($Location; $Location.displayName; $Location.countriesAndRegions; $Location.ipRanges; $Location.ipRanges.cidrAddress)) {
                    if ($Value -is [string] -and $Value -match '^%[^%\s]+%$') { $Value }
                }
            }
        }
    ) | Select-Object -Unique
}
