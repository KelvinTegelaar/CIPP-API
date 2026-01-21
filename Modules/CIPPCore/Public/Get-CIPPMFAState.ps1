function Get-CIPPMFAState {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $APIName = 'Get MFA Status',
        $Headers
    )
    #$PerUserMFAState = Get-CIPPPerUserMFA -TenantFilter $TenantFilter -AllUsers $true
    $users = foreach ($user in (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$top=999&$select=id,UserPrincipalName,DisplayName,accountEnabled,assignedLicenses,perUserMfaState' -tenantid $TenantFilter)) {
        [PSCustomObject]@{
            UserPrincipalName = $user.UserPrincipalName
            isLicensed        = [boolean]$user.assignedLicenses.Count
            accountEnabled    = $user.accountEnabled
            DisplayName       = $user.DisplayName
            ObjectId          = $user.id
            perUserMfaState   = $user.perUserMfaState
        }
    }

    $Errors = [System.Collections.Generic.List[object]]::new()
    $SecureDefaultsState = $null
    $CASuccess = $false
    $CAError = $null
    $PolicyTable = @{}
    $AllUserPolicies = @()
    $UserGroupMembership = @{}
    $UserExcludeGroupMembership = @{}
    $GroupNameLookup = @{}
    $MFAIndex = @{}

    try {
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $TenantFilter ).IsEnabled
    } catch {
        Write-Host "Secure Defaults not available: $($_.Exception.Message)"
        $Errors.Add(@{Step = 'SecureDefaults'; Message = $_.Exception.Message })
        $SecureDefaultsState = $null
    }
    $CAState = [System.Collections.Generic.List[object]]::new()

    try {
        $MFARegistration = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?`$top=999&`$select=userPrincipalName,isMfaRegistered,isMfaCapable,methodsRegistered" -tenantid $TenantFilter -asapp $true)
        foreach ($MFAEntry in $MFARegistration) {
            if ($null -ne $MFAEntry.userPrincipalName) {
                $MFAIndex[$MFAEntry.userPrincipalName] = $MFAEntry
            }
        }
    } catch {
        $CAState.Add('Not Licensed for Conditional Access') | Out-Null
        $MFARegistration = $null
        $CAError = "MFA registration not available - licensing required for Conditional Access reporting"
        if ($_.Exception.Message -ne "Tenant is not a B2C tenant and doesn't have premium licenses") {
            $Errors.Add(@{Step = 'MFARegistration'; Message = $_.Exception.Message })
        }
        Write-Host "User registration details not available: $($_.Exception.Message)"
    }

    if ($null -ne $MFARegistration) {
        try {
            $CASuccess = $true
            $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999&$filter=state eq ''enabled''&$select=id,displayName,state,grantControls,conditions' -tenantid $TenantFilter -ErrorAction Stop -AsApp $true)
            $PolicyTable = @{}
            $AllUserPolicies = [System.Collections.Generic.List[object]]::new()
            $GroupsToResolve = [System.Collections.Generic.HashSet[string]]::new()
            $ExcludeGroupsToResolve = [System.Collections.Generic.HashSet[string]]::new()

            foreach ($Policy in $CAPolicies) {
                # Only include policies that require MFA
                $RequiresMFA = $false
                if ($Policy.grantControls.builtInControls -contains 'mfa') {
                    $RequiresMFA = $true
                }
                # Check for authentication strength requiring MFA
                if ($Policy.grantControls.authenticationStrength.requirementsSatisfied -eq 'mfa') {
                    $RequiresMFA = $true
                }

                if ($RequiresMFA) {
                    # Handle user assignments
                    if ($Policy.conditions.users.includeUsers -ne $null) {
                        # Check if "All" is included
                        if ($Policy.conditions.users.includeUsers -contains 'All') {
                            $AllUserPolicies.Add($Policy)
                        } else {
                            foreach ($UserId in $Policy.conditions.users.includeUsers) {
                                if (-not $PolicyTable.ContainsKey($UserId)) {
                                    $PolicyTable[$UserId] = [System.Collections.Generic.List[object]]::new()
                                }
                                $PolicyTable[$UserId].Add($Policy)
                            }
                        }
                    }

                    # Collect groups to resolve
                    if ($Policy.conditions.users.includeGroups -ne $null -and $Policy.conditions.users.includeGroups.Count -gt 0) {
                        foreach ($GroupId in $Policy.conditions.users.includeGroups) {
                            [void]$GroupsToResolve.Add($GroupId)
                        }
                    }

                    # Collect exclude groups to resolve
                    if ($Policy.conditions.users.excludeGroups -ne $null -and $Policy.conditions.users.excludeGroups.Count -gt 0) {
                        foreach ($GroupId in $Policy.conditions.users.excludeGroups) {
                            [void]$ExcludeGroupsToResolve.Add($GroupId)
                        }
                    }
                }
            }

            # Resolve group memberships using bulk request
            $UserGroupMembership = @{}
            $UserExcludeGroupMembership = @{}
            $GroupNameLookup = @{}

            if ($GroupsToResolve.Count -gt 0 -or $ExcludeGroupsToResolve.Count -gt 0) {
                $GroupMemberRequests = [system.collections.generic.list[object]]::new()
                $GroupDetailsRequests = [system.collections.generic.list[object]]::new()
                Write-Information "Resolving group memberships for $($GroupsToResolve.Count) include groups and $($ExcludeGroupsToResolve.Count) exclude groups"
                # Add include group requests
                foreach ($GroupId in $GroupsToResolve) {
                    $GroupMemberRequests.Add(@{
                            id     = "include-$GroupId"
                            method = 'GET'
                            url    = "groups/$($GroupId)/members?`$select=id"
                        })
                    $GroupDetailsRequests.Add(@{
                            id     = "details-$GroupId"
                            method = 'GET'
                            url    = "groups/$($GroupId)?`$select=id,displayName"
                        })
                }

                # Add exclude group requests
                foreach ($GroupId in $ExcludeGroupsToResolve) {
                    $GroupMemberRequests.Add(@{
                            id     = "exclude-$GroupId"
                            method = 'GET'
                            url    = "groups/$($GroupId)/members?`$select=id"
                        })
                    $GroupDetailsRequests.Add(@{
                            id     = "details-$GroupId"
                            method = 'GET'
                            url    = "groups/$($GroupId)?`$select=id,displayName"
                        })
                }

                $GroupMembersResults = New-GraphBulkRequest -Requests @($GroupMemberRequests) -tenantid $TenantFilter
                $GroupDetailsResults = New-GraphBulkRequest -Requests @($GroupDetailsRequests) -tenantid $TenantFilter

                # Build group name lookup
                $GroupNameLookup = @{}
                foreach ($GroupDetail in $GroupDetailsResults) {
                    if ($GroupDetail.status -eq 200 -and $GroupDetail.body) {
                        $GroupId = $GroupDetail.id -replace '^details-', ''
                        $GroupNameLookup[$GroupId] = $GroupDetail.body.displayName
                        Write-Host "Added group to lookup: $GroupId = $($GroupDetail.body.displayName)"
                    } else {
                        Write-Host "Failed to get group details: $($GroupDetail.id) - Status: $($GroupDetail.status)"
                    }
                }

                # Build mapping of user to groups they're in
                foreach ($GroupResult in $GroupMembersResults) {
                    if ($GroupResult.status -eq 200 -and $GroupResult.body.value) {
                        $IsExclude = $GroupResult.id -like 'exclude-*'
                        $GroupId = $GroupResult.id -replace '^(include-|exclude-)', ''

                        foreach ($Member in $GroupResult.body.value) {
                            if ($IsExclude) {
                                if (-not $UserExcludeGroupMembership.ContainsKey($Member.id)) {
                                    $UserExcludeGroupMembership[$Member.id] = [System.Collections.Generic.HashSet[string]]::new()
                                }
                                [void]$UserExcludeGroupMembership[$Member.id].Add($GroupId)
                            } else {
                                if (-not $UserGroupMembership.ContainsKey($Member.id)) {
                                    $UserGroupMembership[$Member.id] = [System.Collections.Generic.HashSet[string]]::new()
                                }
                                [void]$UserGroupMembership[$Member.id].Add($GroupId)
                            }
                        }
                    }
                }

                # Now add policies to users based on group membership
                foreach ($Policy in $CAPolicies | Where-Object { $_.conditions.users.includeGroups -ne $null -and $_.conditions.users.includeGroups.Count -gt 0 }) {
                    # Check if this policy requires MFA
                    $RequiresMFA = $false
                    if ($Policy.grantControls.builtInControls -contains 'mfa') {
                        $RequiresMFA = $true
                    }
                    if ($Policy.grantControls.authenticationStrength.requirementsSatisfied -eq 'mfa') {
                        $RequiresMFA = $true
                    }

                    if ($RequiresMFA) {
                        foreach ($UserId in $UserGroupMembership.Keys) {
                            # Check if user is member of any of the policy's included groups
                            $IsMember = $false
                            foreach ($GroupId in $Policy.conditions.users.includeGroups) {
                                if ($UserGroupMembership[$UserId].Contains($GroupId)) {
                                    $IsMember = $true
                                    break
                                }
                            }

                            if ($IsMember) {
                                if (-not $PolicyTable.ContainsKey($UserId)) {
                                    $PolicyTable[$UserId] = [System.Collections.Generic.List[object]]::new()
                                }
                                $PolicyTable[$UserId].Add($Policy)
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

    if ($CAState.count -eq 0) { $CAState.Add('None') | Out-Null }

    $assignments = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal" -tenantid $TenantFilter -ErrorAction SilentlyContinue

    $adminObjectIds = $assignments |
        Where-Object {
            $_.principal.'@odata.type' -eq '#microsoft.graph.user'
        } |
        ForEach-Object {
            $_.principal.id
        }

    # Interact with query parameters or the body of the request.
    $GraphRequest = $Users | ForEach-Object {
        $UserCAState = [System.Collections.Generic.List[object]]::new()

        # Add policies that apply to this specific user
        if ($PolicyTable.ContainsKey($_.ObjectId)) {
            foreach ($Policy in $PolicyTable[$_.ObjectId]) {
                # Check if user is excluded directly or via group
                $IsExcluded = $Policy.conditions.users.excludeUsers -contains $_.ObjectId
                $ExcludedViaGroup = $null

                # Check exclude groups
                if (-not $IsExcluded -and $Policy.conditions.users.excludeGroups -ne $null -and $Policy.conditions.users.excludeGroups.Count -gt 0) {
                    if ($UserExcludeGroupMembership.ContainsKey($_.ObjectId)) {
                        foreach ($ExcludeGroupId in $Policy.conditions.users.excludeGroups) {
                            if ($UserExcludeGroupMembership[$_.ObjectId].Contains($ExcludeGroupId)) {
                                $IsExcluded = $true
                                $ExcludedViaGroup = if ($GroupNameLookup.ContainsKey($ExcludeGroupId)) {
                                    $GroupNameLookup[$ExcludeGroupId]
                                } else {
                                    $ExcludeGroupId
                                }
                                break
                            }
                        }
                    }
                }

                $PolicyObj = [PSCustomObject]@{
                    DisplayName  = $Policy.displayName
                    UserIncluded = -not $IsExcluded
                    AllApps      = ($Policy.conditions.applications.includeApplications -contains 'All')
                    PolicyState  = $Policy.state
                }
                if ($ExcludedViaGroup) {
                    $PolicyObj | Add-Member -NotePropertyName 'ExcludedViaGroup' -NotePropertyValue $ExcludedViaGroup
                }
                $UserCAState.Add($PolicyObj)
            }
        }

        # Add policies that apply to all users
        foreach ($Policy in $AllUserPolicies) {
            # Check if user is excluded directly or via group
            $IsExcluded = $Policy.conditions.users.excludeUsers -contains $_.ObjectId
            $ExcludedViaGroup = $null

            # Check exclude groups
            if (-not $IsExcluded -and $Policy.conditions.users.excludeGroups -ne $null -and $Policy.conditions.users.excludeGroups.Count -gt 0) {
                if ($UserExcludeGroupMembership.ContainsKey($_.ObjectId)) {
                    foreach ($ExcludeGroupId in $Policy.conditions.users.excludeGroups) {
                        if ($UserExcludeGroupMembership[$_.ObjectId].Contains($ExcludeGroupId)) {
                            $IsExcluded = $true
                            $ExcludedViaGroup = if ($GroupNameLookup.ContainsKey($ExcludeGroupId)) {
                                $GroupNameLookup[$ExcludeGroupId]
                            } else {
                                $ExcludeGroupId
                            }
                            break
                        }
                    }
                }
            }

            # Always add the policy to show it applies (even if excluded)
            $PolicyObj = [PSCustomObject]@{
                DisplayName  = $Policy.displayName
                UserIncluded = -not $IsExcluded
                AllApps      = ($Policy.conditions.applications.includeApplications -contains 'All')
                PolicyState  = $Policy.state
            }
            if ($ExcludedViaGroup) {
                $PolicyObj | Add-Member -NotePropertyName 'ExcludedViaGroup' -NotePropertyValue $ExcludedViaGroup
            }
            $UserCAState.Add($PolicyObj)
        }

        # Determine if user is covered by CA
        if ($UserCAState.Count -gt 0 -and ($UserCAState | Where-Object { $_.UserIncluded -eq $true -and $_.PolicyState -eq 'enabled' })) {
            $EnabledPolicies = $UserCAState | Where-Object { $_.UserIncluded -eq $true -and $_.PolicyState -eq 'enabled' }
            if ($EnabledPolicies | Where-Object { $_.AllApps -eq $true }) {
                $CoveredByCA = 'Enforced - All Apps'
            } else {
                $CoveredByCA = 'Enforced - Specific Apps'
            }
        } else {
            if ($CASuccess -eq $false) {
                $CoveredByCA = $CAError
            } else {
                $CoveredByCA = 'Not Enforced'
            }
        }
        $IsAdmin = if ($adminObjectIds -contains $_.ObjectId) { $true } else { $false }

        $PerUser = $_.PerUserMFAState

        $MFARegUser = $MFAIndex[$_.UserPrincipalName]

        [PSCustomObject]@{
            Tenant          = $TenantFilter
            ID              = $_.ObjectId
            UPN             = $_.UserPrincipalName
            DisplayName     = $_.DisplayName
            AccountEnabled  = $_.accountEnabled
            PerUser         = $PerUser
            isLicensed      = $_.isLicensed
            MFARegistration = if ($null -ne $MFARegUser) { [bool]$MFARegUser.isMfaRegistered } else { $null }
            MFACapable      = if ($null -ne $MFARegUser) { [bool]$MFARegUser.isMfaCapable } else { $null }
            MFAMethods      = if ($null -ne $MFARegUser) { @($MFARegUser.methodsRegistered) } else { @() }
            CoveredByCA     = $CoveredByCA
            CAPolicies      = @($UserCAState)
            CoveredBySD     = $SecureDefaultsState
            IsAdmin         = $IsAdmin
            RowKey          = [string]($_.UserPrincipalName).replace('#', '')
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
    return $GraphRequest
}
