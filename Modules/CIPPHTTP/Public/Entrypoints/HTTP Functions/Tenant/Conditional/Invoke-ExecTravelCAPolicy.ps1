function Invoke-ExecTravelCAPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param(
        $Request,
        $TriggerMetadata,
        $tenantFilter,
        $Users,
        $StartDate,
        $EndDate,
        $BlockPolicies,
        $NamedLocations,
        $CountryCodes,
        $IncludeTrusted,
        $RetryAttempt,
        $CountryLocationId
    )
    $Headers = $Request.Headers

    try {
        if (-not $TenantFilter)  { $TenantFilter   = $Request.Body.tenantFilter }
        if (-not $Users)         { $Users          = $Request.Body.Users }
        if (-not $StartDate)     { $StartDate      = $Request.Body.StartDate }
        if (-not $EndDate)       { $EndDate        = $Request.Body.EndDate }
        if (-not $BlockPolicies) { $BlockPolicies  = $Request.Body.BlockPolicies }
        if (-not $NamedLocations){ $NamedLocations = $Request.Body.NamedLocations }
        if (-not $CountryCodes)  { $CountryCodes   = $Request.Body.CountryCodes }
        if (-not $IncludeTrusted){ $IncludeTrusted = $Request.Body.IncludeTrusted }
        $RetryAttempt = [int]($RetryAttempt ?? $Request.Body.RetryAttempt ?? 0)
        if (-not $CountryLocationId) { $CountryLocationId = $Request.Body.CountryLocationId }

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

        # Build date strings for policy name using configured timezone (falls back to UTC if not configured)
        try {
            $ConfigTable = Get-CIPPTable -TableName Config
            $TimeSettings = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'TimeSettings' and RowKey eq 'TimeSettings'"
            $ScheduleTimeZone = if ($TimeSettings.Timezone) { [TimeZoneInfo]::FindSystemTimeZoneById($TimeSettings.Timezone) } else { [TimeZoneInfo]::Utc }
        } catch {
            $ScheduleTimeZone = [TimeZoneInfo]::Utc
        }
        $StartStr   = [TimeZoneInfo]::ConvertTimeFromUtc([datetimeoffset]::FromUnixTimeSeconds($StartDate).UtcDateTime, $ScheduleTimeZone).ToString('yyyyMMdd')
        $EndStr     = [TimeZoneInfo]::ConvertTimeFromUtc([datetimeoffset]::FromUnixTimeSeconds($EndDate).UtcDateTime, $ScheduleTimeZone).ToString('yyyyMMdd')
        $PolicyName = "TravelPolicy_${StartStr}_${EndStr}"

        #region --- 1. Check/create TravelingUsers group ---
        $ExistingGroups = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=displayName eq 'TravelingUsers'&`$select=id,displayName&`$count=true" -tenantid $TenantFilter -asApp $true -ComplexFilter

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
            $CurrentPolicy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)?`$select=id,displayName,conditions" -tenantid $TenantFilter -asApp $true

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
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$PolicyId" -tenantid $TenantFilter -type PATCH -body $PatchBody -asApp $true
                Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' -message "Added TravelingUsers exclusion to CA policy: $($CurrentPolicy.displayName)" -Sev 'Info' -tenant $TenantFilter
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
            $AllLocations = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter -asApp $true
            $TrustedLocations = $AllLocations | Where-Object { $_.isTrusted -eq $true }
            foreach ($TrustedLoc in $TrustedLocations) {
                if ($IncludeLocationIds -notcontains $TrustedLoc.id) {
                    $IncludeLocationIds.Add($TrustedLoc.id)
                }
            }
        }

        # Create a country-based Named Location if country codes were provided.
        # On retry, CountryLocationId is passed directly to skip re-creation.
        if ($CountryCodes -and $CountryCodes.Count -gt 0) {
            $CountryLocationName = "Travel_${StartStr}_${EndStr}_Countries"
            if ($CountryLocationId) {
                # Reuse existing Named Location from previous attempt
                $IncludeLocationIds.Add($CountryLocationId)
                Write-Information "Reusing existing Named Location from retry: $CountryLocationId"
            } else {
                $CountryLocationBody = @{
                    '@odata.type'                     = '#microsoft.graph.countryNamedLocation'
                    displayName                       = $CountryLocationName
                    countriesAndRegions               = @($CountryCodes)
                    includeUnknownCountriesAndRegions = $false
                } | ConvertTo-Json -Compress
                try {
                    $NewLocation = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' -tenantid $TenantFilter -type POST -body $CountryLocationBody -asApp $true
                } catch {
                    $LocError = Get-CippException -Exception $_
                    if ($LocError.NormalizedError -match '1048') { throw "One or more selected country codes are not supported by Microsoft Graph. Please remove unsupported countries and try again. Error: $($LocError.NormalizedError)" }
                    throw
                }
                $CountryLocationId = $NewLocation.id
                $IncludeLocationIds.Add($CountryLocationId)
                Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' -message "Created country Named Location: $CountryLocationName ($($CountryCodes -join ', '))" -Sev 'Info' -tenant $TenantFilter
            }
        }
        #endregion

        #region --- 4. Build and create travel CA policy ---
        $PolicyId = $null
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
            $CreatedPolicy = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $TenantFilter -type POST -body $TravelPolicyBody -asApp $true
            $PolicyId = $CreatedPolicy.id
            Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' -message "Created travel CA policy: $PolicyName ($PolicyId) for users: $($UserUPNs -join ', ')" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            # If Named Location has not yet propagated (error 1040), schedule a retry task
            if ($ErrorMessage.NormalizedError -match '1040' -and $CountryLocationId -and $RetryAttempt -lt 3) {
                $RetryEpoch = ([DateTimeOffset][DateTime]::UtcNow.AddMinutes(3)).ToUnixTimeSeconds()
                $RetryTask = [pscustomobject]@{
                    TenantFilter  = $TenantFilter
                    Name          = "Vacation Travel - Retry policy creation: $PolicyName"
                    Command       = @{ value = 'Invoke-ExecTravelCAPolicy'; label = 'Invoke-ExecTravelCAPolicy' }
                    Parameters    = [pscustomobject]@{
                        TenantFilter      = $TenantFilter
                        Users             = $Users
                        StartDate         = $StartDate
                        EndDate           = $EndDate
                        BlockPolicies     = $BlockPolicies
                        NamedLocations    = $NamedLocations
                        CountryCodes      = $CountryCodes
                        IncludeTrusted    = $IncludeTrusted
                        CountryLocationId = $CountryLocationId
                        RetryAttempt      = $RetryAttempt + 1
                    }
                    ScheduledTime = $RetryEpoch
                }
                Add-CIPPScheduledTask -Task $RetryTask -DesiredStartTime ([string]$RetryEpoch) -hidden $false
                Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' -message "Named Location not yet propagated, retrying policy creation in 3 minutes" -Sev 'Info' -tenant $TenantFilter
                $body = @{ Results = "Travel setup in progress. Named Location is propagating - policy creation will retry at the next scheduled interval (within 15 minutes)." }
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $body })
            }
            throw
        }
        #endregion

        #region --- 5. Schedule tasks ---
        $UserMembers = $UserUPNs ?? $UserIds

        $AddMemberTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Vacation Travel - Add to group: $PolicyName"
            Command       = @{ value = 'Add-CIPPGroupMember'; label = 'Add-CIPPGroupMember' }
            Parameters    = [pscustomobject]@{
                GroupType = 'Security'
                GroupId   = $TravelGroupId
                Member    = $UserMembers
            }
            ScheduledTime = if ($StartDate -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } else { $StartDate }
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }
        Add-CIPPScheduledTask -Task $AddMemberTask -hidden $false -RunNow

        $DeletePolicyTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Vacation Travel - Delete policy: $PolicyName"
            Command       = @{ value = 'Remove-CIPPTravelCAPolicy'; label = 'Remove-CIPPTravelCAPolicy' }
            Parameters    = [pscustomobject]@{
                TenantFilter = $TenantFilter
                PolicyName   = $PolicyName
                PolicyId     = $PolicyId
                Users        = @($UserIds)
            }
            ScheduledTime = $EndDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }
        Add-CIPPScheduledTask -Task $DeletePolicyTask -hidden $false

        if ($CountryLocationId) {
            $DeleteLocationTask = [pscustomobject]@{
                TenantFilter  = $TenantFilter
                Name          = "Vacation Travel - Delete Named Location: $PolicyName"
                Command       = @{ value = 'Remove-CIPPTravelNamedLocation'; label = 'Remove-CIPPTravelNamedLocation' }
                Parameters    = [pscustomobject]@{
                    TenantFilter = $TenantFilter
                    PolicyName   = $PolicyName
                    LocationId   = $CountryLocationId
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
        Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' -message "Failed to set up travel mode: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $body = @{ Results = "Failed to set up travel mode: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
}
