function Get-CIPPMFAState {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get MFA Status',
        $Headers
    )
    $B2BCategories = @('b2bCollaborationGuest', 'b2bCollaborationMember')
    $ExtDomainPattern = '^.+_(?<domain>[^_#]+)#EXT#@'
    $DomainTenantLookup = @{}
    $UnresolvedDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    #$PerUserMFAState = Get-CIPPPerUserMFA -TenantFilter $TenantFilter -AllUsers $true
    $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$top=999&$select=id,UserPrincipalName,DisplayName,accountEnabled,assignedLicenses,perUserMfaState,userType' -tenantid $TenantFilter

    $Errors = [System.Collections.Generic.List[object]]::new()
    $SecureDefaultsState = $null
    $CASuccess = $false
    $CAError = $null
    $PolicyTable = @{}
    $MFASpecs = [System.Collections.Generic.List[object]]::new()
    $AllUserSpecs = [System.Collections.Generic.List[object]]::new()
    $GuestUserSpecs = [System.Collections.Generic.List[object]]::new()
    $GuestScopedSpecs = [System.Collections.Generic.List[object]]::new()
    $UserExcludeGroupMembership = @{}
    $GroupNameLookup = @{}
    $UserExcludeRoleMembership = @{}
    $RoleNameLookup = @{}
    $MFAIndex = @{}
    $NeedsTenantLookup = $false

    try {
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter ).IsEnabled
    } catch {
        Write-Host "Secure Defaults not available: $($_.Exception.Message)"
        $Errors.Add(@{Step = 'SecureDefaults'; Message = $_.Exception.Message })
        $SecureDefaultsState = $null
    }

    try {
        $MFARegistration = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&`$select=userPrincipalName,isMfaRegistered,isMfaCapable,methodsRegistered" -tenantid $TenantFilter -asapp $true)
        foreach ($MFAEntry in $MFARegistration) {
            if ($null -ne $MFAEntry.userPrincipalName) {
                $MFAIndex[$MFAEntry.userPrincipalName] = $MFAEntry
            }
        }
    } catch {
        $MFARegistration = $null
        $CAError = 'MFA registration not available - licensing required for Conditional Access reporting'
        if ($_.Exception.Message -ne "Tenant is not a B2C tenant and doesn't have premium licenses") {
            $Errors.Add(@{Step = 'MFARegistration'; Message = $_.Exception.Message })
        }
        Write-Host "User registration details not available: $($_.Exception.Message)"
    }

    if ($null -ne $MFARegistration) {
        try {
            $CASuccess = $true
            $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999&$filter=state eq ''enabled''&$select=id,displayName,state,grantControls,conditions' -tenantid $TenantFilter -ErrorAction Stop -AsApp $true)
            $GroupsToResolve = [System.Collections.Generic.HashSet[string]]::new()
            $ExcludeGroupsToResolve = [System.Collections.Generic.HashSet[string]]::new()
            $RolesToResolve = [System.Collections.Generic.HashSet[string]]::new()
            $ExcludeRolesToResolve = [System.Collections.Generic.HashSet[string]]::new()

            # Fetch role assignments and definitions early for role-targeted CA policies
            $assignments = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal" -tenantid $TenantFilter -ErrorAction SilentlyContinue
            $roleDefinitions = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$select=id,templateId,displayName" -tenantid $TenantFilter -ErrorAction SilentlyContinue

            # Build lookup tables: CA policies use templateId, assignments use definitionId
            $TemplateToDefinitionId = @{}
            foreach ($rd in $roleDefinitions) {
                if ($null -ne $rd.templateId) {
                    $TemplateToDefinitionId[$rd.templateId] = $rd.id
                    $RoleNameLookup[$rd.templateId] = $rd.displayName
                }
            }

            foreach ($Policy in $CAPolicies) {
                if ($Policy.grantControls.builtInControls -notcontains 'mfa' -and $Policy.grantControls.authenticationStrength.requirementsSatisfied -ne 'mfa') { continue }
                $Conditions = $Policy.conditions.users
                $AllApps = $Policy.conditions.applications.includeApplications -contains 'All'
                $ExcludeUsers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($UserId in $Conditions.excludeUsers) { [void]$ExcludeUsers.Add($UserId) }

                # [0] include, [1] exclude: the legacy 'GuestsOrExternalUsers' user token or the guest block
                $GuestSides = foreach ($Side in 'include', 'exclude') {
                    $Block = $Conditions."$($Side)GuestsOrExternalUsers"
                    @{
                        Legacy     = $Conditions."$($Side)Users" -contains 'GuestsOrExternalUsers'
                        Types      = @(([string]$Block.guestOrExternalUserTypes -split ',').Trim()) -ne ''
                        Enumerated = [string]$Block.externalTenants.membershipKind -eq 'enumerated'
                        Tenants    = @(foreach ($TenantId in $Block.externalTenants.members) { $TenantId })
                    }
                }

                # Rows share these read-only policy entries instead of building one per user per policy
                $Spec = @{
                    Id               = $Policy.id
                    Enabled          = $Policy.state -eq 'enabled'
                    AllApps          = $AllApps
                    ExcludeUsers     = $ExcludeUsers
                    IncludeGroups    = @(foreach ($GroupId in $Conditions.includeGroups) { $GroupId })
                    ExcludeGroups    = @(foreach ($GroupId in $Conditions.excludeGroups) { $GroupId })
                    IncludeRoles     = @(foreach ($RoleId in $Conditions.includeRoles) { $RoleId })
                    ExcludeRoles     = @(foreach ($RoleId in $Conditions.excludeRoles) { $RoleId })
                    GuestSides       = $GuestSides
                    Included         = [PSCustomObject]@{ DisplayName = $Policy.displayName; UserIncluded = $true; AllApps = $AllApps; PolicyState = $Policy.state }
                    Unknown          = [PSCustomObject]@{ DisplayName = $Policy.displayName; UserIncluded = $null; AllApps = $AllApps; PolicyState = $Policy.state }
                    Excluded         = [PSCustomObject]@{ DisplayName = $Policy.displayName; UserIncluded = $false; AllApps = $AllApps; PolicyState = $Policy.state }
                    ExcludedViaGroup = @{}
                    ExcludedViaRole  = @{}
                }
                $MFASpecs.Add($Spec)

                if ($GuestSides[0].Legacy -or $GuestSides[1].Legacy -or $GuestSides[0].Types.Count -gt 0 -or $GuestSides[1].Types.Count -gt 0) {
                    $GuestScopedSpecs.Add($Spec)
                }
                if ($GuestSides[0].Legacy -or $GuestSides[0].Types.Count -gt 0) {
                    $GuestUserSpecs.Add($Spec)
                }
                foreach ($Side in $GuestSides) {
                    if ($Side.Enumerated -and ($Side.Types -contains 'b2bCollaborationGuest' -or $Side.Types -contains 'b2bCollaborationMember')) { $NeedsTenantLookup = $true }
                }

                if ($Conditions.includeUsers -contains 'All') {
                    $AllUserSpecs.Add($Spec)
                } else {
                    foreach ($UserId in $Conditions.includeUsers) {
                        if ($UserId -eq 'GuestsOrExternalUsers') { continue }
                        if (-not $PolicyTable.ContainsKey($UserId)) {
                            $PolicyTable[$UserId] = [System.Collections.Generic.List[object]]::new()
                        }
                        $PolicyTable[$UserId].Add($Spec)
                    }
                }

                foreach ($GroupId in $Spec.IncludeGroups) { [void]$GroupsToResolve.Add($GroupId) }
                foreach ($GroupId in $Spec.ExcludeGroups) { [void]$ExcludeGroupsToResolve.Add($GroupId) }
                foreach ($RoleId in $Spec.IncludeRoles) { [void]$RolesToResolve.Add($RoleId) }
                foreach ($RoleId in $Spec.ExcludeRoles) { [void]$ExcludeRolesToResolve.Add($RoleId) }
            }

            # Resolve group memberships using bulk request
            if ($GroupsToResolve.Count -gt 0 -or $ExcludeGroupsToResolve.Count -gt 0) {
                $UserGroupMembership = @{}
                $GroupMemberRequests = [system.collections.generic.list[object]]::new()
                $GroupDetailsRequests = [system.collections.generic.list[object]]::new()
                Write-Information "Resolving group memberships for $($GroupsToResolve.Count) include groups and $($ExcludeGroupsToResolve.Count) exclude groups"
                foreach ($GroupId in $GroupsToResolve) {
                    $GroupMemberRequests.Add(@{ id = "include-$GroupId"; method = 'GET'; url = "groups/$($GroupId)/members?`$select=id" })
                    $GroupDetailsRequests.Add(@{ id = "details-$GroupId"; method = 'GET'; url = "groups/$($GroupId)?`$select=id,displayName" })
                }
                foreach ($GroupId in $ExcludeGroupsToResolve) {
                    $GroupMemberRequests.Add(@{ id = "exclude-$GroupId"; method = 'GET'; url = "groups/$($GroupId)/members?`$select=id" })
                    $GroupDetailsRequests.Add(@{ id = "details-$GroupId"; method = 'GET'; url = "groups/$($GroupId)?`$select=id,displayName" })
                }

                $GroupMembersResults = New-GraphBulkRequest -Requests @($GroupMemberRequests) -tenantid $TenantFilter
                $GroupDetailsResults = New-GraphBulkRequest -Requests @($GroupDetailsRequests) -tenantid $TenantFilter

                foreach ($GroupDetail in $GroupDetailsResults) {
                    if ($GroupDetail.status -eq 200 -and $GroupDetail.body) {
                        $GroupNameLookup[($GroupDetail.id -replace '^details-', '')] = $GroupDetail.body.displayName
                    } else {
                        Write-Host "Failed to get group details: $($GroupDetail.id) - Status: $($GroupDetail.status)"
                    }
                }

                foreach ($GroupResult in $GroupMembersResults) {
                    if ($GroupResult.status -eq 200 -and $GroupResult.body.value) {
                        $Membership = if ($GroupResult.id -like 'exclude-*') { $UserExcludeGroupMembership } else { $UserGroupMembership }
                        $GroupId = $GroupResult.id -replace '^(include-|exclude-)', ''
                        foreach ($Member in $GroupResult.body.value) {
                            if (-not $Membership.ContainsKey($Member.id)) {
                                $Membership[$Member.id] = [System.Collections.Generic.HashSet[string]]::new()
                            }
                            [void]$Membership[$Member.id].Add($GroupId)
                        }
                    }
                }

                foreach ($Spec in $MFASpecs) {
                    if ($Spec.IncludeGroups.Count -eq 0) { continue }
                    foreach ($UserId in $UserGroupMembership.Keys) {
                        foreach ($GroupId in $Spec.IncludeGroups) {
                            if ($UserGroupMembership[$UserId].Contains($GroupId)) {
                                if (-not $PolicyTable.ContainsKey($UserId)) {
                                    $PolicyTable[$UserId] = [System.Collections.Generic.List[object]]::new()
                                }
                                $PolicyTable[$UserId].Add($Spec)
                                break
                            }
                        }
                    }
                }
            }

            # Resolve role memberships from already-fetched $assignments
            if ($RolesToResolve.Count -gt 0 -or $ExcludeRolesToResolve.Count -gt 0) {
                $UserRoleMembership = @{}
                $AllRoleTemplateIds = [System.Collections.Generic.HashSet[string]]::new()
                $AllRoleTemplateIds.UnionWith($RolesToResolve)
                $AllRoleTemplateIds.UnionWith($ExcludeRolesToResolve)

                # Map each assignment's definitionId back to templateId
                foreach ($assignment in $assignments) {
                    if ($assignment.principal.'@odata.type' -ne '#microsoft.graph.user') { continue }
                    $principalId = $assignment.principalId
                    $defId = $assignment.roleDefinitionId

                    foreach ($templateId in $AllRoleTemplateIds) {
                        # Match: either the definition ID maps from this template, or for built-in roles they're equal
                        if ($defId -eq $TemplateToDefinitionId[$templateId] -or $defId -eq $templateId) {
                            if ($RolesToResolve.Contains($templateId)) {
                                if (-not $UserRoleMembership.ContainsKey($principalId)) {
                                    $UserRoleMembership[$principalId] = [System.Collections.Generic.HashSet[string]]::new()
                                }
                                [void]$UserRoleMembership[$principalId].Add($templateId)
                            }
                            if ($ExcludeRolesToResolve.Contains($templateId)) {
                                if (-not $UserExcludeRoleMembership.ContainsKey($principalId)) {
                                    $UserExcludeRoleMembership[$principalId] = [System.Collections.Generic.HashSet[string]]::new()
                                }
                                [void]$UserExcludeRoleMembership[$principalId].Add($templateId)
                            }
                        }
                    }
                }

                foreach ($Spec in $MFASpecs) {
                    if ($Spec.IncludeRoles.Count -eq 0) { continue }
                    foreach ($UserId in $UserRoleMembership.Keys) {
                        foreach ($RoleId in $Spec.IncludeRoles) {
                            if ($UserRoleMembership[$UserId].Contains($RoleId)) {
                                if (-not $PolicyTable.ContainsKey($UserId)) {
                                    $PolicyTable[$UserId] = [System.Collections.Generic.List[object]]::new()
                                }
                                $PolicyTable[$UserId].Add($Spec)
                                break
                            }
                        }
                    }
                }
            }
        } catch {
            $CASuccess = $false
            $CAError = "CA policies not available: $($_.Exception.Message)"
            $Errors.Add(@{Step = 'CAPolicies'; Message = $_.Exception.Message })
        }
    }

    # Graph users carry no home tenant id, so the #EXT# UPN domain stands in for it (wrong if the guest redeemed with another identity)
    if ($NeedsTenantLookup) {
        $ExternalDomains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($User in $Users) {
            if ([string]$User.userPrincipalName -match $ExtDomainPattern) { [void]$ExternalDomains.Add($Matches.domain) }
        }
        if ($ExternalDomains.Count -gt 0) {
            $DomainRequests = foreach ($Domain in $ExternalDomains) {
                @{ id = $Domain; method = 'GET'; url = "tenantRelationships/findTenantInformationByDomainName(domainName='$Domain')" }
            }
            $UnresolvedDomains.UnionWith($ExternalDomains)
            try {
                foreach ($Result in @(New-GraphBulkRequest -Requests @($DomainRequests) -tenantid $TenantFilter -asapp $true)) {
                    $Domain = [string]$Result.id
                    if ($Result.status -eq 200 -and $Result.body.tenantId) {
                        $DomainTenantLookup[$Domain] = [string]$Result.body.tenantId
                        [void]$UnresolvedDomains.Remove($Domain)
                    } elseif ($Result.status -in 400, 404) {
                        # Not an Entra tenant: a definite "no home tenant", not a failure
                        [void]$UnresolvedDomains.Remove($Domain)
                    }
                }
            } catch {
                Write-Host "External tenant lookup failed: $($_.Exception.Message)"
                $Errors.Add(@{Step = 'ExternalTenants'; Message = $_.Exception.Message })
            }
            if ($UnresolvedDomains.Count -gt 0) {
                $Errors.Add(@{Step = 'ExternalTenants'; Message = "Could not resolve the home tenant for $($UnresolvedDomains.Count) external domain(s): $($UnresolvedDomains -join ', ')" })
            }
        }
    }

    # Fetch role assignments if not already fetched (e.g., when MFA registration was unavailable)
    if ($null -eq $assignments) {
        $assignments = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal" -tenantid $TenantFilter -ErrorAction SilentlyContinue
    }

    $adminObjectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Assignment in $assignments) {
        if ($Assignment.principal.'@odata.type' -eq '#microsoft.graph.user') { [void]$adminObjectIds.Add([string]$Assignment.principal.id) }
    }

    $UserCAState = [System.Collections.Generic.List[object]]::new()
    $GuestCandidates = [System.Collections.Generic.List[object]]::new()
    $IncludeUnknown = [System.Collections.Generic.HashSet[string]]::new()
    $GuestVerdicts = @{}

    # Rows are emitted as they are built so a streaming caller never holds the whole tenant.
    foreach ($User in $Users) {
        $UserId = $User.id
        $Upn = [string]$User.userPrincipalName
        $UserCAState.Clear()

        $IsExt = $Upn.Contains('#EXT#', [System.StringComparison]::OrdinalIgnoreCase)
        $GuestCategory = if ($User.userType -eq 'Guest') { if ($IsExt) { 'b2bCollaborationGuest' } else { 'internalGuest' } } elseif ($IsExt) { 'b2bCollaborationMember' } else { $null }
        $GuestList = $null
        if ($GuestCategory) {
            # Per guest-scoped policy: [include, exclude] as $true / $false / $null (home tenant lookup failed)
            $GuestVerdicts.Clear()
            $GuestCandidates.Clear()
            $IncludeUnknown.Clear()
            $IsB2B = $GuestCategory -in $B2BCategories
            $ExternalDomain = if ($IsExt -and $Upn -match $ExtDomainPattern) { $Matches.domain }
            $HomeUnknown = $ExternalDomain -and $UnresolvedDomains.Contains($ExternalDomain)
            $HomeTenantId = if ($ExternalDomain) { $DomainTenantLookup[$ExternalDomain] }
            foreach ($Spec in $GuestScopedSpecs) {
                $GuestVerdicts[$Spec.Id] = foreach ($Side in $Spec.GuestSides) {
                    if ($Side.Legacy) { $true }
                    elseif ($Side.Types -notcontains $GuestCategory) { $false }
                    elseif (-not $IsB2B -or -not $Side.Enumerated) { $true }
                    elseif ($HomeUnknown) { $null }
                    else { [bool]($HomeTenantId -and $Side.Tenants -contains $HomeTenantId) }
                }
            }
            foreach ($Spec in $GuestUserSpecs) {
                $IncludeMatch, $GuestExcluded = $GuestVerdicts[$Spec.Id]
                if ($IncludeMatch -ne $false -and $GuestExcluded -ne $true) {
                    $GuestCandidates.Add($Spec)
                    if ($null -eq $IncludeMatch) { [void]$IncludeUnknown.Add($Spec.Id) }
                }
            }
            $GuestList = $GuestCandidates
        }

        $UserExcludeGroups = $UserExcludeGroupMembership[$UserId]
        $UserExcludeRoles = $UserExcludeRoleMembership[$UserId]
        $HasEnabledPolicy = $false
        $HasAllAppsPolicy = $false
        $HasIndeterminatePolicy = $false
        $FromGuestList = $true
        # Guest-targeted, then direct/group/role-assigned, then All users policies
        foreach ($SpecList in $GuestList, $PolicyTable[$UserId], $AllUserSpecs) {
            foreach ($Spec in $SpecList) {
                $IsExcluded = $Spec.ExcludeUsers.Contains($UserId)
                $Indeterminate = $FromGuestList -and $IncludeUnknown.Contains($Spec.Id)
                if (-not $IsExcluded -and $GuestCategory -and $GuestVerdicts.ContainsKey($Spec.Id)) {
                    $GuestExcluded = $GuestVerdicts[$Spec.Id][1]
                    if ($GuestExcluded) { $IsExcluded = $true } elseif ($null -eq $GuestExcluded) { $Indeterminate = $true }
                }

                $PolicyObj = $null
                if (-not $IsExcluded -and $UserExcludeGroups) {
                    foreach ($GroupId in $Spec.ExcludeGroups) {
                        if ($UserExcludeGroups.Contains($GroupId)) {
                            $IsExcluded = $true
                            $PolicyObj = $Spec.ExcludedViaGroup[$GroupId]
                            if (-not $PolicyObj) {
                                $PolicyObj = $Spec.Excluded.PSObject.Copy()
                                $PolicyObj | Add-Member -NotePropertyName 'ExcludedViaGroup' -NotePropertyValue $(if ($GroupNameLookup.ContainsKey($GroupId)) { $GroupNameLookup[$GroupId] } else { $GroupId })
                                $Spec.ExcludedViaGroup[$GroupId] = $PolicyObj
                            }
                            break
                        }
                    }
                }
                if (-not $IsExcluded -and $UserExcludeRoles) {
                    foreach ($RoleId in $Spec.ExcludeRoles) {
                        if ($UserExcludeRoles.Contains($RoleId)) {
                            $IsExcluded = $true
                            $PolicyObj = $Spec.ExcludedViaRole[$RoleId]
                            if (-not $PolicyObj) {
                                $PolicyObj = $Spec.Excluded.PSObject.Copy()
                                $PolicyObj | Add-Member -NotePropertyName 'ExcludedViaRole' -NotePropertyValue $(if ($RoleNameLookup.ContainsKey($RoleId)) { $RoleNameLookup[$RoleId] } else { $RoleId })
                                $Spec.ExcludedViaRole[$RoleId] = $PolicyObj
                            }
                            break
                        }
                    }
                }

                if ($IsExcluded) {
                    if (-not $PolicyObj) { $PolicyObj = $Spec.Excluded }
                } elseif ($Indeterminate) {
                    $PolicyObj = $Spec.Unknown
                    if ($Spec.Enabled) { $HasIndeterminatePolicy = $true }
                } else {
                    $PolicyObj = $Spec.Included
                    if ($Spec.Enabled) {
                        $HasEnabledPolicy = $true
                        if ($Spec.AllApps) { $HasAllAppsPolicy = $true }
                    }
                }
                $UserCAState.Add($PolicyObj)
            }
            $FromGuestList = $false
        }

        if ($HasEnabledPolicy) {
            $CoveredByCA = if ($HasAllAppsPolicy) { 'Enforced - All Apps' } else { 'Enforced - Specific Apps' }
        } elseif ($CASuccess -eq $false) {
            $CoveredByCA = $CAError
        } elseif ($HasIndeterminatePolicy) {
            $CoveredByCA = 'Unknown - external tenant lookup failed'
        } else {
            $CoveredByCA = 'Not Enforced'
        }

        $MFARegUser = $MFAIndex[$Upn]

        [PSCustomObject]@{
            Tenant          = $TenantFilter
            ID              = $UserId
            UPN             = $User.userPrincipalName
            DisplayName     = $User.displayName
            AccountEnabled  = $User.accountEnabled
            PerUser         = $User.perUserMfaState
            isLicensed      = [boolean]$User.assignedLicenses.Count
            MFARegistration = if ($null -ne $MFARegUser) { [bool]$MFARegUser.isMfaRegistered } else { $null }
            MFACapable      = if ($null -ne $MFARegUser) { [bool]$MFARegUser.isMfaCapable } else { $null }
            MFAMethods      = if ($null -ne $MFARegUser) { @($MFARegUser.methodsRegistered) } else { @() }
            CoveredByCA     = $CoveredByCA
            CAPolicies      = $UserCAState.ToArray()
            CoveredBySD     = $SecureDefaultsState
            IsAdmin         = $adminObjectIds.Contains([string]$UserId)
            UserType        = $User.userType
            RowKey          = $Upn.Replace('#', '')
            PartitionKey    = 'users'
        }
    }
    $ErrorCount = ($Errors | Measure-Object).Count
    if ($ErrorCount -gt 0) {
        if ($ErrorCount -gt 1) {
            $Text = 'errors'
        } else {
            $Text = 'an error'
        }
        Write-LogMessage -headers $Headers -API $APIName -Tenant $TenantFilter -message "The MFA report encountered $Text, see log data for details." -Sev 'Error' -LogData @($Errors.Message)
    }
}
