function New-CIPPCATemplate {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $JSON,
        $APIName = 'Add CIPP CA Template',
        $Headers,
        $preloadedUsers,
        $preloadedGroups,
        $preloadedLocations
    )

    $JSON = ([pscustomobject]$JSON) | ForEach-Object {
        $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
        $_ | Select-Object -Property $NonEmptyProperties
    }

    Write-Information "Processing CA Template for tenant $TenantFilter"
    Write-Information ($JSON | ConvertTo-Json -Depth 10)

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
    if ($preloadedLocations) {
        $namedLocations = $preloadedLocations
    } else {
        if ($JSON.conditions.locations.includeLocations -or $JSON.conditions.locations.excludeLocations) {
            $namedLocations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter
        }
    }

    $AllLocations = [system.collections.generic.list[object]]::new()

    $includelocations = [system.collections.generic.list[object]]::new()
    $IncludeJSON = foreach ($Location in $JSON.conditions.locations.includeLocations) {
        $locationinfo = $namedLocations | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $includelocations.add($locationinfo.displayName) } else { $includelocations.add($location) }
        $locationinfo
    }
    if ($includelocations) {
        $JSON.conditions.locations | Add-Member -NotePropertyName 'includeLocations' -NotePropertyValue $includelocations -Force
    }

    $excludelocations = [system.collections.generic.list[object]]::new()
    $ExcludeJSON = foreach ($Location in $JSON.conditions.locations.excludeLocations) {
        $locationinfo = $namedLocations | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $excludelocations.add($locationinfo.displayName) } else { $excludelocations.add($location) }
        $locationinfo
    }

    if ($excludelocations) {
        $JSON.conditions.locations | Add-Member -NotePropertyName 'excludeLocations' -NotePropertyValue $excludelocations -Force
    }
    # Check if conditions.users exists and is a PSCustomObject (not an array) before accessing properties
    $hasConditionsUsers = $null -ne $JSON.conditions.users
    # Explicitly exclude array types - arrays have properties but we can't set custom properties on them
    $isArray = $hasConditionsUsers -and ($JSON.conditions.users -is [Array] -or $JSON.conditions.users -is [System.Collections.IList])
    $isPSCustomObject = $hasConditionsUsers -and -not $isArray -and ($JSON.conditions.users -is [PSCustomObject] -or ($JSON.conditions.users.PSObject.Properties.Count -gt 0 -and -not $isArray))
    $hasIncludeUsers = $isPSCustomObject -and ($null -ne $JSON.conditions.users.includeUsers)

    if ($isPSCustomObject -and $hasIncludeUsers) {
        $JSON.conditions.users.includeUsers = @($JSON.conditions.users.includeUsers | ForEach-Object {
                $originalID = $_
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers') { return $_ }
                $match = $users | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }

    # Use the same type check for other user properties
    if ($isPSCustomObject -and $null -ne $JSON.conditions.users.excludeUsers) {
        $JSON.conditions.users.excludeUsers = @($JSON.conditions.users.excludeUsers | ForEach-Object {
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers') { return $_ }
                $originalID = $_
                $match = $users | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }

    if ($isPSCustomObject -and $null -ne $JSON.conditions.users.includeGroups) {
        $JSON.conditions.users.includeGroups = @($JSON.conditions.users.includeGroups | ForEach-Object {
                $originalID = $_
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers' -or -not (Test-IsGuid -String $_)) { return $_ }
                $match = $groups | Where-Object { $_.id -eq $originalID }
                if ($match) { $match.displayName } else { $originalID }
            })
    }
    if ($isPSCustomObject -and $null -ne $JSON.conditions.users.excludeGroups) {
        $JSON.conditions.users.excludeGroups = @($JSON.conditions.users.excludeGroups | ForEach-Object {
                $originalID = $_
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers' -or -not (Test-IsGuid -String $_)) { return $_ }
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

    # Remove duplicates based on displayName to avoid Select-Object -Unique issues with complex objects
    $UniqueLocations = $AllLocations | Group-Object -Property displayName | ForEach-Object { $_.Group[0] }
    $JSON | Add-Member -NotePropertyName 'LocationInfo' -NotePropertyValue @($UniqueLocations) -Force
    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject $JSON)
    return $JSON
}

