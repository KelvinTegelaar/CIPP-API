function New-CIPPCATemplate {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $JSON,
        $APIName = 'Add CIPP CA Template',
        $Headers,
        $preloadedUsers,
        $preloadedGroups
    )

    $JSON = ([pscustomobject]$JSON) | ForEach-Object {
        $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
        $_ | Select-Object -Property $NonEmptyProperties
    }

    Write-Information "Processing CA Template for tenant $TenantFilter"
    Write-Information ($JSON | ConvertTo-Json -Depth 10)

    # Function to check if a string is a GUID
    function Test-IsGuid($string) {
        return [guid]::tryparse($string, [ref][guid]::Empty)
    }

    if ($preloadedUsers) {
        $users = $preloadedUsers
    } else {
        $users = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=displayName,id" -tenantid $TenantFilter)
    }
    if ($preloadedGroups) {
        $groups = $preloadedGroups
    } else {
        $groups = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$top=999&`$select=displayName,id" -tenantid $TenantFilter)
    }

    $namedLocations = $null
    if ($JSON.conditions.locations.includeLocations -or $JSON.conditions.locations.excludeLocations) {
        $namedLocations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $TenantFilter
    }

    $AllLocations = [system.collections.generic.list[object]]::new()

    $includelocations = [system.collections.generic.list[object]]::new()
    $IncludeJSON = foreach ($Location in $JSON.conditions.locations.includeLocations) {
        $locationinfo = $namedLocations | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $includelocations.add($locationinfo.displayName) } else { $includelocations.add($location) }
        $locationinfo
    }
    if ($includelocations) { $JSON.conditions.locations.includeLocations = $includelocations }

    $excludelocations = [system.collections.generic.list[object]]::new()
    $ExcludeJSON = foreach ($Location in $JSON.conditions.locations.excludeLocations) {
        $locationinfo = $namedLocations | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $excludelocations.add($locationinfo.displayName) } else { $excludelocations.add($location) }
        $locationinfo
    }

    if ($excludelocations) { $JSON.conditions.locations.excludeLocations = $excludelocations }
    if ($JSON.conditions.users.includeUsers) {
        $JSON.conditions.users.includeUsers = @($JSON.conditions.users.includeUsers | ForEach-Object {
                $originalID = $_
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers') { return $_ }
                $match = $users | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }

    if ($JSON.conditions.users.excludeUsers) {
        $JSON.conditions.users.excludeUsers = @($JSON.conditions.users.excludeUsers | ForEach-Object {
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers') { return $_ }
                $originalID = $_
                $match = $users | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }

    if ($JSON.conditions.users.includeGroups) {
        $JSON.conditions.users.includeGroups = @($JSON.conditions.users.includeGroups | ForEach-Object {
                $originalID = $_
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers' -or -not (Test-IsGuid $_)) { return $_ }
                $match = $groups | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }
    if ($JSON.conditions.users.excludeGroups) {
        $JSON.conditions.users.excludeGroups = @($JSON.conditions.users.excludeGroups | ForEach-Object {
                $originalID = $_
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers' -or -not (Test-IsGuid $_)) { return $_ }
                $match = $groups | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }

    foreach ($Location in $IncludeJSON) {
        $AllLocations.Add($Location)
    }
    foreach ($Location in $ExcludeJSON) {
        $AllLocations.Add($Location)
    }

    $JSON | Add-Member -NotePropertyName 'LocationInfo' -NotePropertyValue @($AllLocations | Select-Object -Unique) -Force
    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject $JSON)
    return $JSON
}

