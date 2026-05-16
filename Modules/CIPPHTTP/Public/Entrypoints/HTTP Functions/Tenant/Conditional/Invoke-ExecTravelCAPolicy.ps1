function Invoke-ExecTravelCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers

    try {
        $TenantFilter   = $Request.Body.tenantFilter
        $Users          = $Request.Body.Users
        $StartDate      = $Request.Body.StartDate
        $EndDate        = $Request.Body.EndDate
        $BlockPolicies  = $Request.Body.BlockPolicies
        $NamedLocations = $Request.Body.NamedLocations
        $CountryCodes   = $Request.Body.CountryCodes
        $IncludeTrusted = $Request.Body.IncludeTrusted
        $RetryAttempt   = [int]($Request.Body.RetryAttempt ?? 0)

        # Build user lists
        $UserUPNs = $Users.addedFields.userPrincipalName
        $UserIds  = $Users.value
        # Resolve UPNs to object IDs (Graph CA policy requires GUIDs)
        $ResolvedIds = [System.Collections.Generic.List[string]]::new()
        foreach ($UPN in $UserUPNs) {
            try {
                $UserObj = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($UPN)?`$select=id" -tenantid $TenantFilter -asApp $true -ErrorAction Stop
                $ResolvedIds.Add($UserObj.id)
            } catch {
                Write-Information "Could not resolve UPN $UPN to object ID, using value from request"
                $ResolvedIds.Add($UPN)
            }
        }
        if ($ResolvedIds.Count -gt 0) { $UserIds = $ResolvedIds }

        # Build date strings for policy name
        $StartStr   = [datetimeoffset]::FromUnixTimeSeconds($StartDate).ToString('yyyyMMdd')
        $EndStr     = [datetimeoffset]::FromUnixTimeSeconds($EndDate).ToString('yyyyMMdd')
        $PolicyName = "TravelPolicy_${StartStr}_${EndStr}"

        #region --- 1. Check/create TravelingUsers group ---
        $ExistingGroups = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/groups?`$filter=displayName eq 'TravelingUsers'&`$select=id,displayName&`$count=true" `
            -tenantid $TenantFilter -asApp $true -ComplexFilter

        if ($ExistingGroups) {
            $TravelGroupId = $ExistingGroups[0].id
            Write-Information "Using existing TravelingUsers group: $TravelGroupId"
        } else {
            Write-Information 'Creating TravelingUsers group'
            $GroupObject = [PSCustomObject]@{
                groupType       = 'generic'
                displayName     = 'TravelingUsers'
                username        = 'TravelingUsers'
                securityEnabled = $true
            }
            $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $TenantFilter -APIName 'Invoke-ExecTravelCAPolicy'
            if (-not $NewGroup.Success) {
                throw "Failed to create TravelingUsers group: $($NewGroup.Message)"
            }
            $TravelGroupId = $NewGroup.GroupId
            Write-Information "Created TravelingUsers group: $TravelGroupId"
        }
        #endregion

        #region --- 2. Check/add group exclusion to blocking CA policies ---
        foreach ($BlockPolicy in $BlockPolicies) {
            $PolicyId = $BlockPolicy.value ?? $BlockPolicy
            $CurrentPolicy = New-GraphGetRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)?`$select=id,displayName,conditions" `
                -tenantid $TenantFilter -asApp $true

            if ($CurrentPolicy.conditions.users.excludeGroups -notcontains $TravelGroupId) {
                Write-Information "Adding TravelingUsers exclusion to policy: $($CurrentPolicy.displayName)"
                $ExistingExclusions = @($CurrentPolicy.conditions.users.excludeGroups | Where-Object { $_ })
                $ExistingExclusions += $TravelGroupId
                $PatchBody = @{
                    conditions = @{
                        users = @{
                            excludeGroups = $ExistingExclusions
                        }
                    }
                } | ConvertTo-Json -Depth 10 -Compress
                $null = New-GraphPOSTRequest `
                    -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$PolicyId" `
                    -tenantid $TenantFilter -type PATCH -body $PatchBody -asApp $true
                Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
                    -message "Added TravelingUsers exclusion to CA policy: $($CurrentPolicy.displayName)" `
                    -Sev 'Info' -tenant $TenantFilter
            } else {
                Write-Information "TravelingUsers already excluded from policy: $($CurrentPolicy.displayName)"
            }
        }
        #endregion

        #region --- 3. Build includeLocations for travel CA policy ---
        $IncludeLocationIds = [System.Collections.Generic.List[string]]::new()
        $CountryLocationName = $null

        # Add selected Named Locations from tenant
        foreach ($Loc in $NamedLocations) {
            $LocId = $Loc.value ?? $Loc
            if (-not [string]::IsNullOrWhiteSpace($LocId)) {
                $IncludeLocationIds.Add($LocId)
            }
        }

        # Add all Trusted Locations if requested
        if ($IncludeTrusted) {
            $AllLocations = New-GraphGetRequest `
                -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' `
                -tenantid $TenantFilter -asApp $true
            $TrustedLocations = $AllLocations | Where-Object { $_.isTrusted -eq $true }
            foreach ($TrustedLoc in $TrustedLocations) {
                if ($IncludeLocationIds -notcontains $TrustedLoc.id) {
                    $IncludeLocationIds.Add($TrustedLoc.id)
                }
            }
        }

        # Create a country-based Named Location if country codes were provided
        if ($CountryCodes -and $CountryCodes.Count -gt 0) {
            $CountryLocationName = "Travel_${StartStr}_${EndStr}_Countries"
            # Check if Named Location already exists (e.g. on retry)
            $ExistingLocation = New-GraphGetRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?`$filter=displayName eq '$CountryLocationName'&`$select=id,displayName" `
                -tenantid $TenantFilter -asApp $true
            if ($ExistingLocation) {
                $IncludeLocationIds.Add($ExistingLocation[0].id)
                Write-Information "Using existing Named Location: $CountryLocationName ($($ExistingLocation[0].id))"
            } else {
                $CountryLocationBody = @{
                    '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
                    displayName                       = $CountryLocationName
                    countriesAndRegions               = @($CountryCodes)
                    includeUnknownCountriesAndRegions = $false
                } | ConvertTo-Json -Compress
                $NewLocation = New-GraphPOSTRequest `
                    -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' `
                    -tenantid $TenantFilter -type POST -body $CountryLocationBody -asApp $true
                $IncludeLocationIds.Add($NewLocation.id)
                Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
                    -message "Created country Named Location: $CountryLocationName ($($CountryCodes -join ', '))" `
                    -Sev 'Info' -tenant $TenantFilter
            }
        }
        #endregion

        #region --- 4. Build and create travel CA policy ---
        # Check if policy already exists (e.g. on retry)
        $ExistingPolicy = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies?`$filter=displayName eq '$PolicyName'&`$select=id,displayName" `
            -tenantid $TenantFilter -asApp $true
        if ($ExistingPolicy) {
            Write-Information "Travel CA policy already exists: $PolicyName"
        } else {
            $TravelPolicyBody = @{
                displayName   = $PolicyName
                state         = 'enabled'
                conditions    = @{
                    users        = @{
                        includeUsers  = @($UserIds)
                        excludeUsers  = @()
                        includeGroups = @()
                        excludeGroups = @()
                    }
                    applications = @{
                        includeApplications = @('All')
                    }
                    locations    = @{
                        includeLocations = @($IncludeLocationIds)
                        excludeLocations = @()
                    }
                }
                grantControls = @{
                    operator        = 'OR'
                    builtInControls = @('mfa')
                }
            } | ConvertTo-Json -Depth 10 -Compress

            try {
                $null = New-GraphPOSTRequest `
                    -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' `
                    -tenantid $TenantFilter -type POST -body $TravelPolicyBody -asApp $true
                Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
                    -message "Created travel CA policy: $PolicyName for users: $($UserUPNs -join ', ')" `
                    -Sev 'Info' -tenant $TenantFilter
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                # If Named Location hasn't propagated yet (1040), reschedule for next timer window
                if ($ErrorMessage.NormalizedError -match '1040' -and $RetryAttempt -lt 3) {
                    $RetryAtUtc = [Cronos.CronExpression]::Parse('* * * * *').GetNextOccurrence([DateTime]::UtcNow.AddMinutes(15), [TimeZoneInfo]::Utc)
                    $RetryEpoch = ([DateTimeOffset]$RetryAtUtc).ToUnixTimeSeconds()
                    $RetryTask = [PSCustomObject]@{
                        TenantFilter  = $TenantFilter
                        Name          = "Vacation Travel - Retry policy creation: $PolicyName"
                        Command       = @{ value = 'Invoke-ExecTravelCAPolicy'; label = 'Invoke-ExecTravelCAPolicy' }
                        Parameters    = [PSCustomObject]@{
                            tenantFilter   = $TenantFilter
                            Users          = $Users
                            StartDate      = $StartDate
                            EndDate        = $EndDate
                            BlockPolicies  = $BlockPolicies
                            NamedLocations = $NamedLocations
                            CountryCodes   = $CountryCodes
                            IncludeTrusted = $IncludeTrusted
                            RetryAttempt   = $RetryAttempt + 1
                        }
                        ScheduledTime = $RetryEpoch
                    }
                    $null = Add-CIPPScheduledTask -Task $RetryTask -DesiredStartTime ([string]$RetryEpoch)
                    Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
                        -message "Named Location not yet propagated, rescheduling policy creation in ~15 minutes (attempt $($RetryAttempt + 1) of 3)" `
                        -Sev 'Info' -tenant $TenantFilter
                    $body = @{ Results = "Travel mode setup in progress. Named Location is propagating — policy creation rescheduled for ~15 minutes. Check the schedule list for status." }
                    return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $body })
                }
                throw
            }
        }
        #endregion

        #region --- 5. Schedule tasks ---
        $UserMembers = $UserUPNs ?? $UserIds

        # StartDate: Add users to TravelingUsers group
        $AddMemberTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Vacation Travel - Add to group: $PolicyName"
            Command       = @{ value = 'Add-CIPPGroupMember'; label = 'Add-CIPPGroupMember' }
            Parameters    = [pscustomobject]@{
                GroupType = 'Security'
                GroupId   = $TravelGroupId
                Member    = $UserMembers
            }
            ScheduledTime = $StartDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }
        Add-CIPPScheduledTask -Task $AddMemberTask -hidden $false

        # EndDate: Delete travel CA policy and group membership
        $DeletePolicyTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Vacation Travel - Delete policy: $PolicyName"
            Command       = @{ value = 'Remove-CIPPTravelCAPolicy'; label = 'Remove-CIPPTravelCAPolicy' }
            Parameters    = [pscustomobject]@{
                TenantFilter = $TenantFilter
                PolicyName   = $PolicyName
                Users        = @($UserIds)
            }
            ScheduledTime = $EndDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }
        Add-CIPPScheduledTask -Task $DeletePolicyTask -hidden $false

        # EndDate + 5 min: Delete Named Location (after CA policy deletion has propagated)
        if ($CountryLocationName) {
            $DeleteLocationTask = [pscustomobject]@{
                TenantFilter  = $TenantFilter
                Name          = "Vacation Travel - Delete Named Location: $PolicyName"
                Command       = @{ value = 'Remove-CIPPTravelNamedLocation'; label = 'Remove-CIPPTravelNamedLocation' }
                Parameters    = [pscustomobject]@{
                    TenantFilter = $TenantFilter
                    PolicyName   = $PolicyName
                }
                ScheduledTime = $EndDate + 300
                PostExecution = $Request.Body.postExecution
                Reference     = $Request.Body.reference
            }
            Add-CIPPScheduledTask -Task $DeleteLocationTask -hidden $false
        }
        #endregion

        $body = @{
            Results = "Successfully scheduled travel mode for $($UserUPNs -join ', '). Policy '$PolicyName' will be active from $(([datetimeoffset]::FromUnixTimeSeconds($StartDate)).ToString('dd.MM.yyyy')) to $(([datetimeoffset]::FromUnixTimeSeconds($EndDate)).ToString('dd.MM.yyyy'))."
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
            -message "Failed to set up travel mode: $($ErrorMessage.NormalizedError)" `
            -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $body = @{ Results = "Failed to set up travel mode: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
}
