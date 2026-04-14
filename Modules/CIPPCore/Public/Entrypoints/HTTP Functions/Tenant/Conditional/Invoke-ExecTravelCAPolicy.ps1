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
        $TenantFilter  = $Request.Body.tenantFilter
        $Users         = $Request.Body.Users
        $StartDate     = $Request.Body.StartDate
        $EndDate       = $Request.Body.EndDate
        $BlockPolicies = $Request.Body.BlockPolicies  # Array av { value: guid, label: navn }
        $NamedLocations = $Request.Body.NamedLocations # Array av { value: guid, label: navn }
        $CountryCodes  = $Request.Body.CountryCodes    # Array av ISO-koder f.eks. ["SE","PL"]
        $IncludeTrusted = $Request.Body.IncludeTrusted # bool

        # Bygg brukerliste
        $UserUPNs = $Users.addedFields.userPrincipalName
        $UserIds  = $Users.value

        # Datostrenger for policy-navn
        $StartStr = [datetimeoffset]::FromUnixTimeSeconds($StartDate).ToString('yyyyMMdd')
        $EndStr   = [datetimeoffset]::FromUnixTimeSeconds($EndDate).ToString('yyyyMMdd')
        $PolicyName = "CIPP_TravelPolicy_${StartStr}_${EndStr}"

        #region --- 1. Sjekk/opprett CIPP_TravelingUsers-gruppen ---
        $ExistingGroups = New-GraphGetRequest `
            -uri "https://graph.microsoft.com/beta/groups?`$filter=displayName eq 'CIPP_TravelingUsers'&`$select=id,displayName&`$count=true" `
            -tenantid $TenantFilter -asApp $true -ComplexFilter

        if ($ExistingGroups) {
            $TravelGroupId = $ExistingGroups[0].id
            Write-Information "Using existing CIPP_TravelingUsers group: $TravelGroupId"
        } else {
            Write-Information 'Creating CIPP_TravelingUsers group'
            $GroupObject = [PSCustomObject]@{
                groupType       = 'generic'
                displayName     = 'CIPP_TravelingUsers'
                username        = 'CIPP_TravelingUsers'
                securityEnabled = $true
            }
            $NewGroup = New-CIPPGroup -GroupObject $GroupObject -TenantFilter $TenantFilter -APIName 'Invoke-ExecTravelCAPolicy'
            if (-not $NewGroup.Success) {
                throw "Failed to create CIPP_TravelingUsers group: $($NewGroup.Message)"
            }
            $TravelGroupId = $NewGroup.GroupId
            Write-Information "Created CIPP_TravelingUsers group: $TravelGroupId"
            # Vent litt så gruppen propageres
            Start-Sleep -Seconds 5
        }
        #endregion

        #region --- 2. Sjekk/legg til gruppeekskludering på blokkerings-policies ---
        foreach ($BlockPolicy in $BlockPolicies) {
            $PolicyId = $BlockPolicy.value ?? $BlockPolicy
            $CurrentPolicy = New-GraphGetRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$($PolicyId)?`$select=id,displayName,conditions" `
                -tenantid $TenantFilter -asApp $true

            if ($CurrentPolicy.conditions.users.excludeGroups -notcontains $TravelGroupId) {
                Write-Information "Adding CIPP_TravelingUsers exclusion to policy: $($CurrentPolicy.displayName)"
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
                    -message "Added CIPP_TravelingUsers exclusion to CA policy: $($CurrentPolicy.displayName)" `
                    -Sev 'Info' -tenant $TenantFilter
            } else {
                Write-Information "CIPP_TravelingUsers already excluded from policy: $($CurrentPolicy.displayName)"
            }
        }
        #endregion

        #region --- 3. Bygg includeLocations for travel-policyen ---
        $IncludeLocationIds = [System.Collections.Generic.List[string]]::new()

        # Legg til valgte Named Locations fra tenanten
        foreach ($Loc in $NamedLocations) {
            $LocId = $Loc.value ?? $Loc
            if (-not [string]::IsNullOrWhiteSpace($LocId)) {
                $IncludeLocationIds.Add($LocId)
            }
        }

        # Legg til Trusted Locations om valgt
        if ($IncludeTrusted) {
            $AllLocations = New-GraphGetRequest `
                -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?`$top=999" `
                -tenantid $TenantFilter -asApp $true
            $TrustedLocations = $AllLocations | Where-Object { $_.isTrusted -eq $true }
            foreach ($TrustedLoc in $TrustedLocations) {
                if ($IncludeLocationIds -notcontains $TrustedLoc.id) {
                    $IncludeLocationIds.Add($TrustedLoc.id)
                }
            }
        }

        # Opprett Named Location for landkoder om valgt
        if ($CountryCodes -and $CountryCodes.Count -gt 0) {
            $CountryLocationName = "CIPP_Travel_${StartStr}_${EndStr}_Countries"
            $CountryLocationBody = @{
                '@odata.type'        = '#microsoft.graph.countriesAndRegionsDefinition'
                displayName          = $CountryLocationName
                countriesAndRegions  = @($CountryCodes)
                includeUnknownCountriesAndRegions = $false
            } | ConvertTo-Json -Compress

            $NewLocation = New-GraphPOSTRequest `
                -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations' `
                -tenantid $TenantFilter -type POST -body $CountryLocationBody -asApp $true
            $IncludeLocationIds.Add($NewLocation.id)
            Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
                -message "Created country Named Location: $CountryLocationName ($($CountryCodes -join ', '))" `
                -Sev 'Info' -tenant $TenantFilter
            Start-Sleep -Seconds 3
        }
        #endregion

        #region --- 4. Bygg og opprett travel CA-policy ---
        $TravelPolicyBody = @{
            displayName   = $PolicyName
            state         = 'enabled'
            conditions    = @{
                users         = @{
                    includeUsers  = @($UserIds)
                    excludeUsers  = @()
                    includeGroups = @()
                    excludeGroups = @()
                }
                applications  = @{
                    includeApplications = @('All')
                }
                locations     = @{
                    includeLocations = @($IncludeLocationIds)
                    excludeLocations = @()
                }
            }
            grantControls = @{
                operator        = 'OR'
                builtInControls = @('mfa')
            }
        } | ConvertTo-Json -Depth 10 -Compress

        $null = New-GraphPOSTRequest `
            -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' `
            -tenantid $TenantFilter -type POST -body $TravelPolicyBody -asApp $true
        Write-LogMessage -headers $Headers -API 'Invoke-ExecTravelCAPolicy' `
            -message "Created travel CA policy: $PolicyName for users: $($UserUPNs -join ', ')" `
            -Sev 'Info' -tenant $TenantFilter
        #endregion

        #region --- 5. Schedule tasks ---
        $UserMembers = $UserUPNs ?? $UserIds

        # StartDate: Legg brukere til i CIPP_TravelingUsers
        $AddMemberTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Travel Mode - Add to group: $PolicyName"
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

        # EndDate: Fjern brukere fra CIPP_TravelingUsers
        $RemoveMemberTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Travel Mode - Remove from group: $PolicyName"
            Command       = @{ value = 'Remove-CIPPGroupMember'; label = 'Remove-CIPPGroupMember' }
            Parameters    = [pscustomobject]@{
                GroupType = 'Security'
                GroupId   = $TravelGroupId
                Member    = $UserMembers
            }
            ScheduledTime = $EndDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }
        Add-CIPPScheduledTask -Task $RemoveMemberTask -hidden $false

        # EndDate: Slett travel CA-policy
        $DeletePolicyTask = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "Travel Mode - Delete policy: $PolicyName"
            Command       = @{ value = 'Remove-CIPPTravelCAPolicy'; label = 'Remove-CIPPTravelCAPolicy' }
            Parameters    = [pscustomobject]@{
                TenantFilter = $TenantFilter
                PolicyName   = $PolicyName
            }
            ScheduledTime = $EndDate
            PostExecution = $Request.Body.postExecution
            Reference     = $Request.Body.reference
        }
        Add-CIPPScheduledTask -Task $DeletePolicyTask -hidden $false
        #endregion

        $body = @{ Results = "Successfully scheduled travel mode for $($UserUPNs -join ', '). Policy '$PolicyName' will be active from $(([datetimeoffset]::FromUnixTimeSeconds($StartDate)).ToString('dd.MM.yyyy')) to $(([datetimeoffset]::FromUnixTimeSeconds($EndDate)).ToString('dd.MM.yyyy'))." }

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
