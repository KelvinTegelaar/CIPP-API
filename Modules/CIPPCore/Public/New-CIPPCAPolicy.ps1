
function New-CIPPCAPolicy {
    [CmdletBinding()]
    param (
        $RawJSON,
        $TenantFilter,
        $State,
        $Overwrite,
        $APIName = "Create CA Policy",
        $ExecutingUser
    )
    function Remove-EmptyArrays ($Object) {
        if ($Object -is [Array]) {
            foreach ($Item in $Object) { Remove-EmptyArrays $Item }
        }
        elseif ($Object -is [HashTable]) {
            foreach ($Key in @($Object.get_Keys())) {
                if ($Object[$Key] -is [Array] -and $Object[$Key].get_Count() -eq 0) {
                    $Object.Remove($Key)
                }
                else { Remove-EmptyArrays $Object[$Key] }
            }
        }
        elseif ($Object -is [PSCustomObject]) {
            foreach ($Name in @($Object.psobject.properties.Name)) {
                if ($Object.$Name -is [Array] -and $Object.$Name.get_Count() -eq 0) {
                    $Object.PSObject.Properties.Remove($Name)
                }
                elseif ($object.$name -eq $null) {
                    $Object.PSObject.Properties.Remove($Name)
                }
                else { Remove-EmptyArrays $Object.$Name }
            }
        }
    }

    $displayname = ($RawJSON | ConvertFrom-Json).Displayname

    $JSONObj = $RawJSON | ConvertFrom-Json | Select-Object * -ExcludeProperty ID, GUID, *time*
    Remove-EmptyArrays $JSONObj
    #Remove context as it does not belong in the payload.
    $JsonObj.grantControls.PSObject.Properties.Remove('authenticationStrength@odata.context')
    if ($JSONObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.Members) {
        $JsonObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.PSObject.Properties.Remove('@odata.context')
        $JsonObj.conditions.users.excludeGuestsOrExternalUsers.externalTenants.PSObject.Properties.Remove('@odata.type')
    }
    if ($State -and $State -ne 'donotchange') {
        $Jsonobj.state = $State
    }

    #for each of the locations, check if they exist, if not create them. These are in $jsonobj.LocationInfo
    $LocationLookupTable = foreach ($location in $jsonobj.LocationInfo) {
        if (!$location.displayName) { continue }
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -tenantid $TenantFilter
        if ($Location.displayName -in $CheckExististing.displayName) {
            [pscustomobject]@{
                id   = ($CheckExististing | Where-Object -Property displayName -EQ $Location.displayName).id
                name = ($CheckExististing | Where-Object -Property displayName -EQ $Location.displayName).displayName
            }
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Matched a CA policy with the existing Named Location: $($location.displayName)" -Sev "Info"
 
        }
        else {
            $Body = ConvertTo-Json -InputObject $Location
            $GraphRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations" -body $body -Type POST -tenantid $tenantfilter
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Created new Named Location: $($location.displayName)" -Sev "Info"
            [pscustomobject]@{
                id   = $GraphRequest.id
                name = $GraphRequest.displayName
            }
        }
    }
    Write-Host ($LocationLookupTable | ConvertTo-Json)
    foreach ($location in $JSONObj.conditions.locations.includeLocations) {
        Write-Host "Replacting $location"
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

    $JsonObj.PSObject.Properties.Remove('LocationInfo')
    $RawJSON = $JSONObj | ConvertTo-Json -Depth 10
    Write-Host $RawJSON
    try {
        Write-Host "Checking"
        $CheckExististing = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" -tenantid $TenantFilter
        if ($displayname -in $CheckExististing.displayName) {
            if ($Overwrite -ne $true) {
                Throw "Conditional Access Policy with Display Name $($Displayname) Already exists"
                return $false
            }
            else {
                Write-Host "overwriting"
                $PatchRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($CheckExististing.id)" -tenantid $tenantfilter -type PATCH -body $RawJSON
                Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Updated Conditional Access Policy $($JSONObj.Displayname) to the template standard." -Sev "Info"
                return "Updated policy $displayname for $tenantfilter"
            }
        }
        else {
            Write-Host "Creating"
            $CreateRequest = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" -tenantid $tenantfilter -type POST -body $RawJSON
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($Tenant) -message "Added Conditional Access Policy $($JSONObj.Displayname)" -Sev "Info"
            return "Created policy $displayname for $tenantfilter"
        }
    }
    catch {
        throw $_
        Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to create or update conditional access rule $($JSONObj.displayName): $($_.exception.message)" -sev "Error"
    }
}
