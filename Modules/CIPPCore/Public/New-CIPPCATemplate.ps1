function New-CIPPCATemplate {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $JSON,
        $APIName = 'Add CIPP CA Template',
        $ExecutingUser
    )

    $JSON = ([pscustomobject]$JSON) | ForEach-Object {
        $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
        $_ | Select-Object -Property $NonEmptyProperties
    }

    $includelocations = New-Object System.Collections.ArrayList
    $IncludeJSON = foreach ($Location in $JSON.conditions.locations.includeLocations) {
        $locationinfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $TenantFilter | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $includelocations.add($locationinfo.displayName) } else { $includelocations.add($location) }
        $locationinfo
    }
    if ($includelocations) { $JSON.conditions.locations.includeLocations = $includelocations }


    $excludelocations = New-Object System.Collections.ArrayList
    $ExcludeJSON = foreach ($Location in $JSON.conditions.locations.excludeLocations) {
        $locationinfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $TenantFilter | Where-Object -Property id -EQ $location | Select-Object * -ExcludeProperty id, *time*
        $null = if ($locationinfo) { $excludelocations.add($locationinfo.displayName) } else { $excludelocations.add($location) }
        $locationinfo
    }

    if ($excludelocations) { $JSON.conditions.locations.excludeLocations = $excludelocations }
    if ($JSON.conditions.users.includeUsers) {
        $JSON.conditions.users.includeUsers = @($JSON.conditions.users.includeUsers | ForEach-Object {
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers') { return $_ }
                try {
                (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $TenantFilter).displayName
                } catch {
                    return $_
                }
            })
    }

    if ($JSON.conditions.users.excludeUsers) {
        $JSON.conditions.users.excludeUsers = @($JSON.conditions.users.excludeUsers | ForEach-Object {
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers') { return $_ }
                try {
                (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($_)" -tenantid $TenantFilter).displayName
                } catch {
                    return $_
                }
            })
    }

    # Function to check if a string is a GUID
    function Test-IsGuid($string) {
        return [guid]::tryparse($string, [ref][guid]::Empty)
    }

    if ($JSON.conditions.users.includeGroups) {
        $JSON.conditions.users.includeGroups = @($JSON.conditions.users.includeGroups | ForEach-Object {
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers' -or -not (Test-IsGuid $_)) { return $_ }
                try {
                (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($_)" -tenantid $TenantFilter).displayName
                } catch {
                    return $_
                }
            })
    }
    if ($JSON.conditions.users.excludeGroups) {
        $JSON.conditions.users.excludeGroups = @($JSON.conditions.users.excludeGroups | ForEach-Object {
                if ($_ -in 'All', 'None', 'GuestOrExternalUsers' -or -not (Test-IsGuid $_)) { return $_ }
                try {
                (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($_)" -tenantid $TenantFilter).displayName
                } catch {
                    return $_
                }
            })
    }

    $JSON | Add-Member -NotePropertyName 'LocationInfo' -NotePropertyValue @($IncludeJSON, $ExcludeJSON)

    $JSON = (ConvertTo-Json -Compress -Depth 100 -InputObject $JSON)
    return $JSON
}

