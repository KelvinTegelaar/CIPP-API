function Test-CIPPCAGapLocationConditions {
    <#
    .SYNOPSIS
        Reviews the named locations each non-disabled policy references.
    .DESCRIPTION
        Four checks per policy with a location condition: (1) a referenced named location explicitly marked
        not trusted (Medium); (2) the policy uses "All trusted locations" while IP-range named locations in
        the tenant are not trusted, so they silently fall outside the trusted set (High; country locations
        cannot be trusted and are ignored); (3) a referenced location ID that no longer exists (Medium); (4)
        a referenced country location with no countries configured, which never matches (High).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $CountryType = '#microsoft.graph.countryNamedLocation'

    foreach ($Policy in @($Context.Policies)) {
        $Locations = $Policy.conditions.locations
        if ($null -eq $Locations -or $Policy.state -eq 'disabled') { continue }

        $Include = @($Locations.includeLocations)
        $Exclude = @($Locations.excludeLocations)
        $UsesAllTrusted = ($Include -contains 'AllTrusted') -or ($Exclude -contains 'AllTrusted')

        $AllRefs = [System.Collections.Generic.List[string]]::new()
        foreach ($Id in $Include) { $AllRefs.Add("$Id") }
        foreach ($Id in $Exclude) { $AllRefs.Add("$Id") }
        $Sentinels = @('AllTrusted', 'All')

        foreach ($LocationId in $AllRefs) {
            if ($LocationId -in $Sentinels) { continue }
            $Location = $Context.NamedLocationById[$LocationId]
            if ($null -ne $Location -and $Location.isTrusted -eq $false) {
                $Params = @{
                    Severity         = 'Medium'
                    Category         = 'Locations'
                    Title            = "Named location ""$($Location.displayName)"" is not marked as trusted"
                    Description      = 'This policy refers to a network location that is not flagged as trusted. Where the policy also relies on the set of trusted locations, this one falls outside it, and people connecting from there may be blocked or challenged unexpectedly.'
                    Remediation      = "Mark ""$($Location.displayName)"" as trusted if it is a known corporate network, or confirm the policy is meant to treat it as untrusted."
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($LocationId)
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-assignment-network'
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
            }
        }

        if ($UsesAllTrusted) {
            $Untrusted = @($Context.NamedLocations | Where-Object { -not $_.isTrusted -and "$($_.'@odata.type')" -ne $CountryType })
            if ($Untrusted.Count -gt 0) {
                $Names = @($Untrusted | ForEach-Object { "$($_.displayName)" }) -join ', '
                $Params = @{
                    Severity         = 'High'
                    Category         = 'Locations'
                    Title            = "Policy relies on trusted locations while $($Untrusted.Count) defined location(s) are not trusted"
                    Description      = "The following defined network locations are not flagged as trusted and therefore fall outside what this policy treats as trusted: $Names. People connecting from them may be locked out or prompted unexpectedly."
                    Remediation      = 'Flag the locations that represent corporate offices or VPNs as trusted, and confirm the policy behaves as intended for the remaining ones.'
                    AffectedPolicies = @($Policy.displayName)
                    RelatedIds       = @($Untrusted | ForEach-Object { "$($_.id)" })
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-assignment-network'
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
            }
        }

        foreach ($LocationId in $AllRefs) {
            if ($LocationId -in $Sentinels) { continue }
            if ($Context.NamedLocationById.ContainsKey($LocationId)) { continue }
            $Params = @{
                Severity         = 'Medium'
                Category         = 'Locations'
                Title            = 'Policy refers to a network location that no longer exists'
                Description      = 'One of the locations this policy depends on has been deleted. The condition can never match, which silently changes what the policy allows or blocks.'
                Remediation      = 'Remove the stale reference and, if the condition is still needed, point the policy at a current location.'
                AffectedPolicies = @($Policy.displayName)
                RelatedIds       = @($LocationId)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-assignment-network'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }

        foreach ($LocationId in $AllRefs) {
            if ($LocationId -in $Sentinels) { continue }
            $Location = $Context.NamedLocationById[$LocationId]
            if ($null -eq $Location) { continue }
            if ("$($Location.'@odata.type')" -ne $CountryType) { continue }
            if (@($Location.countriesAndRegions | Where-Object { $_ }).Count -gt 0) { continue }
            $Params = @{
                Severity         = 'High'
                Category         = 'Locations'
                Title            = "Country location ""$($Location.displayName)"" has no countries defined"
                Description      = 'The country list behind this location is empty, so the condition never matches. Depending on how it is used, the policy either never applies or its exclusion has no effect.'
                Remediation      = 'Add the intended countries to this location, or remove it from the policy.'
                AffectedPolicies = @($Policy.displayName)
                RelatedIds       = @($LocationId)
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-assignment-network'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }
    }

    @($Findings)
}
