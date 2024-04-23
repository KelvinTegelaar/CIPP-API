
function New-CIPPCAPolicy {
    [CmdletBinding()]
    param (
        $RawJSON,
        $TenantFilter,
        $State,
        $Overwrite,
        $ReplacePattern = 'none',
        $APIName = 'Create CA Policy',
        $ExecutingUser
    )
    function Remove-EmptyArrays ($Object) {
        if ($Object -is [Array]) {
            foreach ($Item in $Object) { Remove-EmptyArrays $Item }
        } elseif ($Object -is [HashTable]) {
            foreach ($Key in @($Object.get_Keys())) {
                if ($Object[$Key] -is [Array] -and $Object[$Key].get_Count() -eq 0) {
                    $Object.Remove($Key)
                } else { Remove-EmptyArrays $Object[$Key] }
            }
        } elseif ($Object -is [PSCustomObject]) {
            foreach ($Name in @($Object.psobject.properties.Name)) {
                if ($Object.$Name -is [Array] -and $Object.$Name.get_Count() -eq 0) {
                    $Object.PSObject.Properties.Remove($Name)
                } elseif ($object.$name -eq $null) {
                    $Object.PSObject.Properties.Remove($Name)
                } else { Remove-EmptyArrays $Object.$Name }
            }
        }
    }
    $displayname = ($RawJSON | ConvertFrom-Json).Displayname

    $JSONObj = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty ID, GUID, *time*
    Remove-EmptyArrays $JSONObj
    #Remove context as it does not belong in the payload.
    try {
        $JsonObj.grantControls.PSObject.Properties.Remove('authenticationStrength@odata.context')
        if ($JSONObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.Members) {
            $JsonObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.PSObject.Properties.Remove('@odata.context')
        }
        if ($State -and $State -ne 'donotchange') {
            $Jsonobj.state = $State
        }
    } catch {
        # no issues here.
    }

    #If Grant Controls contains authenticationstrength, create these and then replace the id
    if ($JSONobj.GrantControls.authenticationStrength.policyType -eq 'custom' -or $JSONobj.GrantControls.authenticationStrength.policyType -eq 'BuiltIn') {
        $ExistingStrength = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies/' -tenantid $TenantFilter | Where-Object -Property displayName -EQ $JSONobj.GrantControls.authenticationStrength.displayName
        if ($ExistingStrength) {
            $JSONObj.GrantControls.authenticationStrength = @{ id = $ExistingStrength.id }

        } else {
            $Body = ConvertTo-Json -InputObject $JSONObj.GrantControls.authenticationStrength
            $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies' -body $body -Type POST -tenantid $tenantfilter
            $JSONObj.GrantControls.authenticationStrength = @{ id = $ExistingStrength.id }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created new Authentication Strength Policy: $($JSONObj.GrantControls.authenticationStrength.displayName)" -Sev 'Info'
        }
    }


    #for each of the locations, check if they exist, if not create them. These are in $jsonobj.LocationInfo
    $LocationLookupTable = foreach ($locations in $jsonobj.LocationInfo) {
        foreach ($location in $locations) {
            if (!$location.displayName) { continue }
            $CheckExististing = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $TenantFilter
            if ($Location.displayName -in $CheckExististing.displayName) {
                [pscustomobject]@{
                    id   = ($CheckExististing | Where-Object -Property displayName -EQ $Location.displayName).id
                    name = ($CheckExististing | Where-Object -Property displayName -EQ $Location.displayName).displayName
                }
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Matched a CA policy with the existing Named Location: $($location.displayName)" -Sev 'Info'
 
            } else {
                if ($location.countriesAndRegions) { $location.countriesAndRegions = @($location.countriesAndRegions) }
                $Body = ConvertTo-Json -InputObject $Location
                Write-Host "Trying to create named location with: $body"
                $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -body $body -Type POST -tenantid $tenantfilter
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created new Named Location: $($location.displayName)" -Sev 'Info'
                [pscustomobject]@{
                    id   = $GraphRequest.id
                    name = $GraphRequest.displayName
                }
            }
        }
    }

    foreach ($location in $JSONObj.conditions.locations.includeLocations) {
        Write-Host "Replacing $location"
        $lookup = $LocationLookupTable | Where-Object -Property name -EQ $location
        Write-Host "Found $lookup"
        if (!$lookup) { continue }
        $index = [array]::IndexOf($JSONObj.conditions.locations.includeLocations, $location)
        $JSONObj.conditions.locations.includeLocations[$index] = $lookup.id
    }

    foreach ($location in $JSONObj.conditions.locations.excludeLocations) {
        $lookup = $LocationLookupTable | Where-Object -Property name -EQ $location
        if (!$lookup) { continue }
        $index = [array]::IndexOf($JSONObj.conditions.locations.excludeLocations, $location)
        $JSONObj.conditions.locations.excludeLocations[$index] = $lookup.id
    }
    switch ($ReplacePattern) {
        'none' {
            Write-Host 'Replacement pattern for inclusions and exclusions is none'
            break
        }
        'AllUsers' {
            Write-Host 'Replacement pattern for inclusions and exclusions is All users. This policy will now apply to everyone.'
            if ($JSONObj.conditions.users.includeUsers -ne 'All') { $JSONObj.conditions.users.includeUsers = @('All') }
            if ($JSONObj.conditions.users.excludeUsers) { $JSONObj.conditions.users.excludeUsers = @() }
            if ($JSONObj.conditions.users.includeGroups) { $JSONObj.conditions.users.includeGroups = @() }
            if ($JSONObj.conditions.users.excludeGroups) { $JSONObj.conditions.users.excludeGroups = @() }
        }
        'displayName' {
            Write-Host 'Replacement pattern for inclusions and exclusions is displayName.'
            $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/users?$select=id,displayName' -tenantid $TenantFilter
            $Groups = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName' -tenantid $TenantFilter
            
            if ($JSONObj.conditions.users.includeUsers -notin 'All', 'None', 'GuestOrExternalUsers') { $JSONObj.conditions.users.includeUsers = @(($users | Where-Object -Property displayName -In $JSONObj.conditions.users.includeUsers).id) }
            if ($JSONObj.conditions.users.excludeUsers) { $JSONObj.conditions.users.excludeUsers = @(($users | Where-Object -Property displayName -In $JSONObj.conditions.users.excludeUsers).id) }
            if ($JSONObj.conditions.users.includeGroups) { $JSONObj.conditions.users.includeGroups = @(($groups | Where-Object -Property displayName -In $JSONObj.conditions.users.includeGroups).id) }
            if ($JSONObj.conditions.users.excludeGroups) { $JSONObj.conditions.users.excludeGroups = @(($groups | Where-Object -Property displayName -In $JSONObj.conditions.users.excludeGroups).id) }
        }
    
    }
    $JsonObj.PSObject.Properties.Remove('LocationInfo')
    $RawJSON = $JSONObj | ConvertTo-Json -Depth 10
    Write-Host $RawJSON
    try {
        Write-Host 'Checking'
        $CheckExististing = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $TenantFilter | Where-Object -Property displayName -EQ $displayname
        if ($CheckExististing) {
            if ($Overwrite -ne $true) {
                Throw "Conditional Access Policy with Display Name $($Displayname) Already exists"
                return $false
            } else {
                Write-Host "overwriting $($CheckExististing.id)"
                $PatchRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated Conditional Access Policy $($JSONObj.Displayname) to the template standard." -Sev 'Info'
                return "Updated policy $displayname for $tenantfilter"
            }
        } else {
            Write-Host 'Creating'
            $CreateRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $tenantfilter -type POST -body $RawJSON
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added Conditional Access Policy $($JSONObj.Displayname)" -Sev 'Info'
            return "Created policy $displayname for $tenantfilter"
        }
    } catch {
        Write-Host "$($_.exception | ConvertTo-Json)"
        throw "Failed to create or update conditional access rule $($JSONObj.displayName): $($_.exception.message)"
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName): $($_.exception.message) " -sev 'Error'
    }
}
