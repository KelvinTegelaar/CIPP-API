function Resolve-CIPPCAPolicyNames {
    <#
    .SYNOPSIS
        Replaces display names in a CA policy's location, user and group conditions with object IDs, in place.
    .DESCRIPTION
        Keywords (All, AllTrusted, None, GuestsOrExternalUsers) and GUIDs pass through. A name is matched by exact
        displayName; one that matches nothing throws an ItemNotFoundException naming it, and one that matches several
        objects throws an ArgumentException, because picking one would silently change who the policy covers.
        Nothing is created. -LocationsOnly (template deploys) keeps their first-match behaviour for a shared location name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        $NamedLocations = $null,
        $PolicyName = $Policy.displayName,
        $LocationNotFoundHint = 'Create it in the tenant first or select an existing named location.',
        [switch]$LocationsOnly,
        $Headers,
        $APIName = 'Create CA Policy'
    )

    $LocationSides = @('includeLocations', 'excludeLocations').Where({ @($Policy.conditions.locations.$_).Where({ $_ -and $_ -notin 'All', 'AllTrusted' -and -not (Test-IsGuid -String $_) }).Count -gt 0 })
    if ($LocationSides.Count -gt 0) {
        if ($null -eq $NamedLocations) {
            $NamedLocations = try {
                New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter -asApp $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                throw "Failed to fetch named locations: $($ErrorMessage.NormalizedError)"
            }
        }
        $TenantLocationIds = @{}
        $LocationNameCounts = @{}
        foreach ($TenantLocation in @($NamedLocations)) {
            if (-not $TenantLocation.displayName) { continue }
            $LocationNameCounts[$TenantLocation.displayName] = 1 + ($LocationNameCounts[$TenantLocation.displayName] ?? 0)
            if (-not $TenantLocationIds.ContainsKey($TenantLocation.displayName)) { $TenantLocationIds[$TenantLocation.displayName] = $TenantLocation.id }
        }
        foreach ($Side in $LocationSides) {
            $Policy.conditions.locations.$Side = @(foreach ($Location in @($Policy.conditions.locations.$Side)) {
                    if (-not $Location -or $Location -in 'All', 'AllTrusted' -or (Test-IsGuid -String $Location)) { $Location; continue }
                    if (-not $TenantLocationIds.ContainsKey($Location)) {
                        throw [System.Management.Automation.ItemNotFoundException]::new("Named location '$Location' used by policy '$PolicyName' was not found in $TenantFilter. $LocationNotFoundHint")
                    }
                    if (-not $LocationsOnly -and $LocationNameCounts[$Location] -gt 1) {
                        throw [System.ArgumentException]::new("Named location '$Location' matches $($LocationNameCounts[$Location]) named locations in $TenantFilter. Select it from the list or use its ID.")
                    }
                    $TenantLocationIds[$Location]
                })
        }
    }

    if ($LocationsOnly) { return }

    $Lookups = @(
        foreach ($Side in 'includeUsers', 'excludeUsers', 'includeGroups', 'excludeGroups') {
            $Kind = if ($Side -like '*Users') { 'users' } else { 'groups' }
            foreach ($Name in @($Policy.conditions.users.$Side)) {
                if ([string]::IsNullOrWhiteSpace($Name) -or (Test-IsGuid -String $Name) -or ($Kind -eq 'users' -and $Name -in 'All', 'None', 'GuestsOrExternalUsers')) { continue }
                @{ Kind = $Kind; Side = $Side; Name = $Name }
            }
        }
    )
    if ($Lookups.Count -eq 0) { return }

    $Requests = [System.Collections.Generic.List[hashtable]]::new()
    $RequestedNames = @{}
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Lookup in $Lookups) {
        if (-not $Seen.Add("$($Lookup.Kind)|$($Lookup.Name)")) { continue }
        $Id = "$($Lookup.Kind)-$($Requests.Count)"
        $RequestedNames[$Id] = $Lookup
        $Filter = [System.Uri]::EscapeDataString("displayName eq '$($Lookup.Name -replace "'", "''")'")
        $Requests.Add(@{ id = $Id; method = 'GET'; url = "$($Lookup.Kind)?`$filter=$Filter&`$select=id,displayName" })
    }
    try {
        $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        throw "Failed to look up users and groups: $($ErrorMessage.NormalizedError)"
    }
    $Users = [System.Collections.Generic.List[object]]::new()
    $Groups = [System.Collections.Generic.List[object]]::new()
    foreach ($Result in @($BulkResults)) {
        if ($Result.status -ge 400) { throw "Failed to look up users and groups: $($Result.body.error.message ?? "Graph returned status $($Result.status)")" }
        $Found = @(@($Result.body.value).Where({ $_ }))
        if ($Found.Count -gt 1) {
            $Lookup = $RequestedNames[$Result.id]
            $Noun = if ($Lookup.Kind -eq 'users') { 'User' } else { 'Group' }
            throw [System.ArgumentException]::new("$Noun '$($Lookup.Name)' matches $($Found.Count) $($Lookup.Kind) in $TenantFilter. Select it from the list or use its object ID.")
        }
        foreach ($Item in $Found) {
            if ($Result.id -like 'users-*') { $Users.Add($Item) } else { $Groups.Add($Item) }
        }
    }

    foreach ($Side in @($Lookups.Side | Select-Object -Unique)) {
        $Policy.conditions.users.$Side = @(if ($Side -like '*Users') {
                Convert-CIPPCAUserNameToId -UserNames $Policy.conditions.users.$Side -Users $Users -Strict $true -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
            } else {
                Convert-CIPPCAGroupNameToId -GroupNames $Policy.conditions.users.$Side -Groups $Groups -CreateGroups $false -NotFoundHint 'Create the group first or select an existing group.' -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
            })
    }
}
