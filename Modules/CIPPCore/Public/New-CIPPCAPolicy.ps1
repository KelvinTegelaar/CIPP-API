
function New-CIPPCAPolicy {
    [CmdletBinding()]
    param (
        $RawJSON,
        $TenantFilter,
        $State,
        $Overwrite,
        $ReplacePattern = 'none',
        $DisableSD = $false,
        $APIName = 'Create CA Policy',
        $Headers
    )

    $User = $Request.Headers

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
                } elseif ($null -eq $object.$name) {
                    $Object.PSObject.Properties.Remove($Name)
                } else { Remove-EmptyArrays $Object.$Name }
            }
        }
    }
    # Function to check if a string is a GUID
    function Test-IsGuid($string) {
        return [guid]::tryparse($string, [ref][guid]::Empty)
    }
    # Helper function to replace group display names with GUIDs
    function Replace-GroupNameWithId {
        param($groupNames)

        $GroupIds = [System.Collections.Generic.List[string]]::new()
        $groupNames | ForEach-Object {
            if (Test-IsGuid $_) {
                Write-LogMessage -Headers $User -API 'Create CA Policy' -message "Already GUID, no need to replace: $_" -Sev 'Debug'
                $GroupIds.Add($_) # it's a GUID, so we keep it
            } else {
                $groupId = ($groups | Where-Object -Property displayName -EQ $_).id # it's a display name, so we get the group ID
                if ($groupId) {
                    foreach ($gid in $groupId) {
                        Write-Warning "Replaced group name $_ with ID $gid"
                        $null = Write-LogMessage -Headers $User -API 'Create CA Policy' -message "Replaced group name $_ with ID $gid" -Sev 'Debug'
                        $GroupIds.Add($gid) # add the ID to the list
                    }
                } else {
                    Write-Warning "Group $_ not found in the tenant"
                }
            }
        }
        return $GroupIds
    }

    function Replace-UserNameWithId {
        param($userNames)

        $UserIds = [System.Collections.Generic.List[string]]::new()
        $userNames | ForEach-Object {
            if (Test-IsGuid $_) {
                Write-LogMessage -Headers $User -API 'Create CA Policy' -message "Already GUID, no need to replace: $_" -Sev 'Debug'
                $UserIds.Add($_) # it's a GUID, so we keep it
            } else {
                $userId = ($users | Where-Object -Property displayName -EQ $_).id # it's a display name, so we get the user ID
                if ($userId) {
                    foreach ($uid in $userId) {
                        Write-Warning "Replaced user name $_ with ID $uid"
                        $null = Write-LogMessage -Headers $User -API 'Create CA Policy' -message "Replaced user name $_ with ID $uid" -Sev 'Debug'
                        $UserIds.Add($uid) # add the ID to the list
                    }
                } else {
                    Write-Warning "User $_ not found in the tenant"
                }
            }
        }
        return $UserIds
    }

    $displayname = ($RawJSON | ConvertFrom-Json).Displayname

    $JSONobj = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty ID, GUID, *time*
    Remove-EmptyArrays $JSONobj
    #Remove context as it does not belong in the payload.
    try {
        $JSONobj.grantControls.PSObject.Properties.Remove('authenticationStrength@odata.context')
        $JSONobj.templateId ? $JSONobj.PSObject.Properties.Remove('templateId') : $null
        if ($JSONobj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.Members) {
            $JSONobj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.PSObject.Properties.Remove('@odata.context')
        }
        if ($State -and $State -ne 'donotchange') {
            $JSONobj.state = $State
        }
    } catch {
        # no issues here.
    }

    #If Grant Controls contains authenticationstrength, create these and then replace the id
    if ($JSONobj.GrantControls.authenticationStrength.policyType -eq 'custom' -or $JSONobj.GrantControls.authenticationStrength.policyType -eq 'BuiltIn') {
        $ExistingStrength = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies/' -tenantid $TenantFilter -asApp $true | Where-Object -Property displayName -EQ $JSONobj.GrantControls.authenticationStrength.displayName
        if ($ExistingStrength) {
            $JSONobj.GrantControls.authenticationStrength = @{ id = $ExistingStrength.id }

        } else {
            $Body = ConvertTo-Json -InputObject $JSONobj.GrantControls.authenticationStrength
            $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies' -body $body -Type POST -tenantid $tenantfilter -asApp $true
            $JSONobj.GrantControls.authenticationStrength = @{ id = $ExistingStrength.id }
            Write-LogMessage -Headers $User -API $APINAME -message "Created new Authentication Strength Policy: $($JSONobj.GrantControls.authenticationStrength.displayName)" -Sev 'Info'
        }
    }

    #for each of the locations, check if they exist, if not create them. These are in $JSONobj.LocationInfo
    $LocationLookupTable = foreach ($locations in $JSONobj.LocationInfo) {
        if (!$locations) { continue }
        foreach ($location in $locations) {
            if (!$location.displayName) { continue }
            $CheckExististing = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $TenantFilter -asApp $true
            if ($Location.displayName -in $CheckExististing.displayName) {
                [pscustomobject]@{
                    id   = ($CheckExististing | Where-Object -Property displayName -EQ $Location.displayName).id
                    name = ($CheckExististing | Where-Object -Property displayName -EQ $Location.displayName).displayName
                }
                Write-LogMessage -Headers $User -API $APINAME -message "Matched a CA policy with the existing Named Location: $($location.displayName)" -Sev 'Info'

            } else {
                if ($location.countriesAndRegions) { $location.countriesAndRegions = @($location.countriesAndRegions) }
                $Body = ConvertTo-Json -InputObject $Location
                $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -body $body -Type POST -tenantid $tenantfilter -asApp $true
                $retryCount = 0
                do {
                    Write-Host "Checking for location $($GraphRequest.id) attempt $retryCount. $TenantFilter"
                    $LocationRequest = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $tenantfilter -asApp $true | Where-Object -Property id -EQ $GraphRequest.id
                    Write-Host "LocationRequest: $($LocationRequest.id)"
                    Start-Sleep -Seconds 2
                    $retryCount++
                } while ((!$LocationRequest -or !$LocationRequest.id) -and ($retryCount -lt 5))
                Write-LogMessage -Headers $User -API $APINAME -message "Created new Named Location: $($location.displayName)" -Sev 'Info'
                [pscustomobject]@{
                    id   = $GraphRequest.id
                    name = $GraphRequest.displayName
                }
            }
        }
    }

    foreach ($location in $JSONobj.conditions.locations.includeLocations) {
        Write-Information "Replacing named location - $location"
        $lookup = $LocationLookupTable | Where-Object -Property name -EQ $location
        Write-Information "Found $lookup"
        if (!$lookup) { continue }
        $index = [array]::IndexOf($JSONobj.conditions.locations.includeLocations, $location)
        $JSONobj.conditions.locations.includeLocations[$index] = $lookup.id
    }

    foreach ($location in $JSONobj.conditions.locations.excludeLocations) {
        $lookup = $LocationLookupTable | Where-Object -Property name -EQ $location
        if (!$lookup) { continue }
        $index = [array]::IndexOf($JSONobj.conditions.locations.excludeLocations, $location)
        $JSONobj.conditions.locations.excludeLocations[$index] = $lookup.id
    }
    switch ($ReplacePattern) {
        'none' {
            Write-Information 'Replacement pattern for inclusions and exclusions is none'
            break
        }
        'AllUsers' {
            Write-Information 'Replacement pattern for inclusions and exclusions is All users. This policy will now apply to everyone.'
            if ($JSONobj.conditions.users.includeUsers -ne 'All') { $JSONobj.conditions.users.includeUsers = @('All') }
            if ($JSONobj.conditions.users.excludeUsers) { $JSONobj.conditions.users.excludeUsers = @() }
            if ($JSONobj.conditions.users.includeGroups) { $JSONobj.conditions.users.includeGroups = @() }
            if ($JSONobj.conditions.users.excludeGroups) { $JSONobj.conditions.users.excludeGroups = @() }
        }
        'displayName' {
            try {
                Write-Information 'Replacement pattern for inclusions and exclusions is displayName.'
                $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/users?$select=id,displayName' -tenantid $TenantFilter -asApp $true
                $groups = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName' -tenantid $TenantFilter -asApp $true

                foreach ($userType in 'includeUsers', 'excludeUsers') {
                    if ($JSONobj.conditions.users.PSObject.Properties.Name -contains $userType -and $JSONobj.conditions.users.$userType -notin 'All', 'None', 'GuestOrExternalUsers') {
                        $JSONobj.conditions.users.$userType = @(Replace-UserNameWithId -userNames $JSONobj.conditions.users.$userType)
                    }
                }

                # Check the included and excluded groups
                foreach ($groupType in 'includeGroups', 'excludeGroups') {
                    if ($JSONobj.conditions.users.PSObject.Properties.Name -contains $groupType) {
                        $JSONobj.conditions.users.$groupType = @(Replace-GroupNameWithId -groupNames $JSONobj.conditions.users.$groupType)
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to replace displayNames for conditional access rule $($JSONobj.displayName). Error: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
                throw "Failed to replace displayNames for conditional access rule $($JSONobj.displayName): $($ErrorMessage.NormalizedError)"
            }
        }
    }
    $JSONobj.PSObject.Properties.Remove('LocationInfo')
    foreach ($condition in $JSONobj.conditions.users.PSObject.Properties.Name) {
        $value = $JSONobj.conditions.users.$condition
        if ($null -eq $value) {
            $JSONobj.conditions.users.$condition = @()
            continue
        }
        if ($value -is [string]) {
            if ([string]::IsNullOrWhiteSpace($value)) {
                $JSONobj.conditions.users.$condition = @()
                continue
            }
        }
        if ($value -is [array]) {
            $nonWhitespaceItems = $value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($nonWhitespaceItems.Count -eq 0) {
                $JSONobj.conditions.users.$condition = @()
                continue
            }
        }
    }
    if ($DisableSD -eq $true) {
        #Send request to disable security defaults.
        $body = '{ "isEnabled": false }'
        try {
            $null = New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -Type patch -Body $body -asApp $true -ContentType 'application/json'
            Write-LogMessage -Headers $User -API 'Create CA Policy' -tenant $($Tenant) -message "Disabled Security Defaults for tenant $($TenantFilter)" -Sev 'Info'
            Start-Sleep 3
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Information "Failed to disable security defaults for tenant $($TenantFilter): $($ErrorMessage.NormalizedError)"
        }
    }
    $RawJSON = ConvertTo-Json -InputObject $JSONobj -Depth 10 -Compress
    Write-Information $RawJSON
    try {
        Write-Information 'Checking for existing policies'
        $CheckExististing = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $TenantFilter -asApp $true | Where-Object -Property displayName -EQ $displayname
        if ($CheckExististing) {
            if ($Overwrite -ne $true) {
                throw "Conditional Access Policy with Display Name $($Displayname) Already exists"
                return $false
            } else {
                if ($State -eq 'donotchange') {
                    $JSONobj.state = $CheckExististing.state
                    $RawJSON = ConvertTo-Json -InputObject $JSONobj -Depth 10 -Compress
                }
                Write-Information "overwriting $($CheckExististing.id)"
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON -asApp $true
                Write-LogMessage -Headers $User -API 'Create CA Policy' -tenant $($Tenant) -message "Updated Conditional Access Policy $($JSONobj.Displayname) to the template standard." -Sev 'Info'
                return "Updated policy $displayname for $tenantfilter"
            }
        } else {
            Write-Information 'Creating new policy'
            if ($JSOObj.GrantControls.authenticationStrength.policyType -or $JSONobj.$JSONobj.LocationInfo) {
                Start-Sleep 3
            }
            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $tenantfilter -type POST -body $RawJSON -asApp $true
            Write-LogMessage -Headers $User -API 'Create CA Policy' -tenant $($Tenant) -message "Added Conditional Access Policy $($JSONobj.Displayname)" -Sev 'Info'
            return "Created policy $displayname for $tenantfilter"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONobj.displayName): $($ErrorMessage.NormalizedError) " -sev 'Error' -LogData $ErrorMessage

        Write-Warning "Failed to create or update conditional access rule $($JSONobj.displayName): $($ErrorMessage.NormalizedError)"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-Information ($JSONobj | ConvertTo-Json -Depth 10)
        throw "Failed to create or update conditional access rule $($JSONobj.displayName): $($ErrorMessage.NormalizedError)"
    }
}
