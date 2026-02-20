function Invoke-ExecAccessTest {
    <#
    .SYNOPSIS
        Tests the complete GDAP (Granular Delegated Admin Privileges) access path for a user.

        This function traces the access path from customer tenant → GDAP relationships → mapped security groups → user,
        checking all 15 standard GDAP roles. It verifies whether a SAM user in the partner tenant has access to each
        role through direct or nested group memberships across all active GDAP relationships for a customer tenant.

        The function returns a role-centric view showing:
        - For each of the 15 GDAP roles: whether it's assigned, whether the user has access, and the complete path
        - Complete traceability: Role → Relationship → Group → User (including nested group paths)
        - Broken path detection: identifies roles assigned but user not a member of the required groups

        The output is structured as JSON suitable for diagram visualization, showing the complete access chain
        regardless of which relationship provides each role.

        Very boilerplate AI code. Needs some simplification and cleanup.
        Ridiculous amount of comments to explain the logic so I don't have to explain it to Claude on the frontend. - rvd

    .DESCRIPTION
        GDAP Access Path Testing:
        1. Validates input parameters (TenantFilter and UPN)
        2. Retrieves customer tenant information
        3. Gets all active GDAP relationships for the customer tenant
        4. Locates the UPN in the partner tenant
        5. Gets user's transitive group memberships (handles nested groups automatically)
        6. For each GDAP relationship:
           - Retrieves all access assignments (mapped security groups)
           - For each group: checks user membership (direct or nested) and traces the path
           - Maps roles to relationships and groups
        7. For each of the 15 GDAP roles:
           - Finds all relationships/groups that have this role assigned
           - Checks if user is a member of any group with this role
           - Builds complete access path showing how user gets the role (if they do)
        8. Returns comprehensive JSON with role-centric view and complete path traces

    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Initialize API logging
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Extract query parameters
    # TenantFilter: The customer tenant ID or domain name to test access for
    # UPN: The User Principal Name of the SAM user in the partner tenant whose access we're testing
    $TenantFilter = $Request.Query.TenantFilter
    $UPN = $Request.Query.UPN

    # Validate required input parameters
    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Error = 'TenantFilter is required' }
        }
    }

    if ([string]::IsNullOrWhiteSpace($UPN)) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Error = 'UPN is required' }
        }
    }

    try {
        # ============================================================================
        # STEP 1: Define all 15 standard GDAP roles
        # ============================================================================
        # These are the roles that should be available through GDAP relationships.
        # Each role has a unique roleDefinitionId (GUID) that Microsoft Graph uses
        # to identify the role. We'll check if the user has access to each of these
        # roles through any GDAP relationship, regardless of which relationship provides it.
        #
        # Note: The roleDefinitionId is the template ID used in Azure AD role definitions.
        # These IDs are consistent across all tenants and are used in GDAP access assignments.
        # ============================================================================

        # Get these from the repo in future -rvd
        $AllGDAPRoles = @(
            @{ Name = 'Application Administrator'; Id = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'; Description = 'Can create and manage all applications, service principals, app registration, enterprise apps, consent requests. Cannot manage directory roles, security groups.' },
            @{ Name = 'Authentication Policy Administrator'; Id = '0526716b-113d-4c15-b2c8-68e3c22b9f80'; Description = 'Configures authentication methods policy, MFA settings, manages Password Protection settings, creates/manages verifiable credentials, Azure support tickets. Restrictions on updating sensitive properties, deleting/restoring users, legacy MFA settings.' },
            @{ Name = 'Billing Administrator'; Id = 'b0f54661-2d74-4c50-afa3-1ec803f12efe'; Description = 'Can perform common billing related tasks like updating payment information.' },
            @{ Name = 'Cloud App Security Administrator'; Id = '892c5842-a9a6-463a-8041-72aa08ca3cf6'; Description = 'Manages all aspects of the Defender for Cloud App Security in Azure AD, including policies, alerts, and related configurations.' },
            @{ Name = 'Cloud Device Administrator'; Id = '7698a772-787b-4ac8-901f-60d6b08affd2'; Description = 'Enables, disables, deletes devices in Azure AD, reads Windows 10 BitLocker keys. Does not grant permissions to manage other properties on the device.' },
            @{ Name = 'Domain Name Administrator'; Id = '8329153a-20ed-4bf8-aa37-81242c6e8e01'; Description = 'Can manage domain names in cloud and on-premises.' },
            @{ Name = 'Exchange Administrator'; Id = '29232cdf-9323-42fd-ade2-1d097af3e4de'; Description = 'Manages all aspects of Exchange Online, including mailboxes, permissions, connectivity, and related settings. Limited access to related Exchange settings in Azure AD.' },
            @{ Name = 'Global Reader'; Id = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'; Description = 'Can read everything that a Global Administrator can but not update anything.' },
            @{ Name = 'Intune Administrator'; Id = '3a2c62db-5318-420d-8d74-23affee5d9d5'; Description = 'Manages all aspects of Intune, including all related resources, policies, configurations, and tasks.' },
            @{ Name = 'Privileged Authentication Administrator'; Id = '7be44c8a-adaf-4e2a-84d6-ab2649e08a13'; Description = 'Sets/resets authentication methods for all users (admin or non-admin), deletes/restores any users. Manages support tickets in Azure and Microsoft 365. Restrictions on managing per-user MFA in legacy MFA portal.' },
            @{ Name = 'Privileged Role Administrator'; Id = 'e8611ab8-c189-46e8-94e1-60213ab1f814'; Description = 'Manages role assignments in Azure AD, Azure AD Privileged Identity Management, creates/manages groups, manages all aspects of Privileged Identity Management, administrative units. Allows managing assignments for all Azure AD roles including Global Administrator.' },
            @{ Name = 'Security Administrator'; Id = '194ae4cb-b126-40b2-bd5b-6091b380977d'; Description = 'Can read security information and reports, and manages security-related features, including identity protection, security policies, device management, and threat management in Azure AD and Office 365.' },
            @{ Name = 'SharePoint Administrator'; Id = 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c'; Description = 'Manages all aspects of SharePoint Online, Microsoft 365 groups, support tickets, service health. Scoped permissions for Microsoft Intune, SharePoint, and OneDrive resources.' },
            @{ Name = 'Teams Administrator'; Id = '69091246-20e8-4a56-aa4d-066075b2a7a8'; Description = 'Manages all aspects of Microsoft Teams, including telephony, messaging, meetings, teams, Microsoft 365 groups, support tickets, and service health.' },
            @{ Name = 'User Administrator'; Id = 'fe930be7-5e62-47db-91af-98c3a49a38b1'; Description = 'Manages all aspects of users, groups, registration, and resets passwords for limited admins. Cannot manage security-related policies or other configuration objects.' }
        )

        # ============================================================================
        # STEP 2: Get customer tenant information
        # ============================================================================
        # The TenantFilter can be either a tenant ID (GUID) or a domain name.
        # Get-Tenants will resolve it and return the tenant object with customerId and displayName.
        # ============================================================================
        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        if (-not $Tenant) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = @{ Error = "Tenant not found: $TenantFilter" }
            }
        }

        $CustomerTenantId = $Tenant.customerId
        $CustomerTenantName = $Tenant.displayName

        # ============================================================================
        # STEP 3: Get all active GDAP relationships for the customer tenant
        # ============================================================================
        # GDAP relationships are created in the partner tenant and link to customer tenants.
        # We query from the partner tenant perspective ($env:TenantID) and filter for:
        # - status eq 'active': Only relationships that are currently active
        # - customer/tenantId eq '$CustomerTenantId': Only relationships for this specific customer
        #
        # A tenant can have multiple GDAP relationships, each potentially with different roles.
        # We need to check all of them to see which roles are available through which relationships.
        # ============================================================================
        $BaseUri = 'https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships'
        $FilterValue = "status eq 'active' and customer/tenantId eq '$CustomerTenantId'"
        $RelationshipsUri = "$($BaseUri)?`$filter=$($FilterValue)"
        $Relationships = New-GraphGetRequest -uri $RelationshipsUri -tenantid $env:TenantID -NoAuthCheck $true

        # If no active relationships exist, return early with an informative message
        if (-not $Relationships -or $Relationships.Count -eq 0) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    tenantId      = $CustomerTenantId
                    tenantName    = $CustomerTenantName
                    relationships = @()
                    error         = "No active GDAP relationships found for tenant $CustomerTenantName"
                }
            }
        }

        # ============================================================================
        # STEP 4: Get the SAM user in the partner tenant
        # ============================================================================
        # The UPN provided is for a user in the PARTNER tenant (not the customer tenant).
        # This is the SAM (Service Account Manager) user whose access we're testing.
        # The user must be in the partner tenant because GDAP groups are in the partner tenant.
        #
        # We try two methods:
        # 1. Filter query: More efficient if it works
        # 2. Direct lookup: Fallback if filter query doesn't return results
        # ============================================================================
        $User = $null
        try {
            # Filter didn't work, try direct lookup by UPN (works if UPN is unique identifier)
            $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UPN" -tenantid $env:TenantID -NoAuthCheck $true
        } catch {
            Write-LogMessage -Headers $Headers -API $APIName -message "Could not find user $UPN in partner tenant: $($_.Exception.Message)" -Sev 'Warning'
        }

        # If user not found, return error
        if (-not $User) {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = @{
                    tenantId      = $CustomerTenantId
                    tenantName    = $CustomerTenantName
                    relationships = @()
                    error         = "User $UPN not found in partner tenant"
                }
            }
        }

        $UserId = $User.id
        $UserDisplayName = $User.displayName

        # ============================================================================
        # STEP 5: Get user's transitive group memberships
        # ============================================================================
        # This is a critical step. We use transitiveMemberOf which automatically handles
        # nested groups at any depth. This means:
        # - If user is directly in Group A, they're included
        # - If user is in Group B, and Group B is in Group A, they're included
        # - If user is in Group C, Group C is in Group B, Group B is in Group A, they're included
        # - And so on for any depth of nesting
        #
        # We build a hashtable (dictionary) for O(1) lookup performance when checking
        # if the user is a member of a specific group later.
        #
        # We filter for only groups (@odata.type = '#microsoft.graph.group') because
        # transitiveMemberOf can also return role assignments, which we don't need here.
        # ============================================================================
        $UserGroupMemberships = @{}
        try {
            # Use AsApp=true to get all memberships regardless of current user context
            $PartnerUserMemberships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserId/transitiveMemberOf?`$select=id,displayName" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -ErrorAction SilentlyContinue
            if ($PartnerUserMemberships) {
                foreach ($Membership in $PartnerUserMemberships) {
                    # Only include groups, not role assignments
                    if ($Membership.'@odata.type' -eq '#microsoft.graph.group') {
                        # Store in hashtable for fast lookup: key = groupId, value = membership object
                        $UserGroupMemberships[$Membership.id] = $Membership
                    }
                }
            }
        } catch {
            Write-LogMessage -Headers $Headers -API $APIName -message "Could not get user group memberships: $($_.Exception.Message)" -Sev 'Warning'
        }

        # ============================================================================
        # STEP 6: Collect all relationships, groups, and build role mapping
        # ============================================================================
        # We need to:
        # 1. For each relationship, get all access assignments (mapped groups)
        # 2. Collect all unique group IDs from all assignments
        # 3. Batch fetch all groups at once (more efficient than individual calls)
        # 4. For each group, check if user is a member and trace the path
        # 5. Build a map from roleId -> list of relationships/groups that have that role
        #
        # This allows us to later check each of the 15 roles and see:
        # - Which relationships have this role
        # - Which groups in those relationships have this role
        # - Whether the user is a member of any of those groups
        # ============================================================================
        $AllRelationshipData = [System.Collections.Generic.List[object]]::new()
        # This map will store: roleId -> list of {relationship, group} objects that have this role assigned
        $RoleToRelationshipsMap = @{}
        # This map will store: roleId -> list of relationships that have this role available (but may not be assigned)
        $RoleToAvailableRelationshipsMap = @{}

        # ========================================================================
        # PHASE 1: Collect all access assignments and extract unique group IDs
        # ========================================================================
        # First, we'll collect all access assignments from all relationships
        # and extract the unique group IDs. Then we'll fetch all groups in batch.
        # Also track which roles are available in each relationship.
        # ========================================================================
        $AllAccessAssignments = [System.Collections.Generic.List[object]]::new()
        $RelationshipAssignmentMap = @{}  # Maps relationshipId -> list of assignments

        foreach ($Relationship in $Relationships) {
            $RelationshipId = $Relationship.id
            $RelationshipName = $Relationship.displayName
            $RelationshipStatus = $Relationship.status

            # Track roles available in this relationship (from accessDetails.unifiedRoles)
            if ($Relationship.accessDetails -and $Relationship.accessDetails.unifiedRoles) {
                foreach ($Role in $Relationship.accessDetails.unifiedRoles) {
                    $RoleId = $Role.roleDefinitionId
                    if ($RoleId) {
                        if (-not $RoleToAvailableRelationshipsMap.ContainsKey($RoleId)) {
                            $RoleToAvailableRelationshipsMap[$RoleId] = [System.Collections.Generic.List[object]]::new()
                        }
                        $RoleToAvailableRelationshipsMap[$RoleId].Add([PSCustomObject]@{
                            relationshipId     = $RelationshipId
                            relationshipName   = $RelationshipName
                            relationshipStatus = $RelationshipStatus
                        })
                    }
                }
            }

            # Get access assignments (mapped security groups) for this relationship
            $AccessAssignments = @()
            try {
                $AccessAssignments = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$RelationshipId/accessAssignments" -tenantid $env:TenantID -NoAuthCheck $true

                # Handle case where response might be a single object instead of array
                if ($AccessAssignments -and -not ($AccessAssignments -is [System.Array])) {
                    $AccessAssignments = @($AccessAssignments)
                }

                Write-LogMessage -Headers $Headers -API $APIName -message "Retrieved $($AccessAssignments.Count) access assignments for relationship ${RelationshipName}" -Sev 'Debug'

                # Store assignments for this relationship
                $RelationshipAssignmentMap[$RelationshipId] = @{
                    Relationship = $Relationship
                    Assignments  = $AccessAssignments
                }

                # Add to master list
                foreach ($Assignment in $AccessAssignments) {
                    $AllAccessAssignments.Add(@{
                        RelationshipId     = $RelationshipId
                        RelationshipName   = $RelationshipName
                        RelationshipStatus = $RelationshipStatus
                        Assignment         = $Assignment
                    })
                }
            } catch {
                Write-LogMessage -Headers $Headers -API $APIName -message "Could not get access assignments for relationship ${RelationshipName}: $($_.Exception.Message)" -Sev 'Warning'
            }
        }

        # Extract all unique group IDs from all assignments
        $AllGroupIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($AssignmentData in $AllAccessAssignments) {
            $Assignment = $AssignmentData.Assignment
            $GroupId = $null

            # Extract group ID from assignment
            if ($Assignment.accessContainer) {
                $GroupId = $Assignment.accessContainer.accessContainerId
            } elseif ($Assignment.value -and $Assignment.value.accessContainer) {
                $GroupId = $Assignment.value.accessContainer.accessContainerId
            }

            if ($GroupId -and -not [string]::IsNullOrWhiteSpace($GroupId)) {
                [void]$AllGroupIds.Add($GroupId)
            }
        }

        Write-LogMessage -Headers $Headers -API $APIName -message "Found $($AllGroupIds.Count) unique groups across all relationships" -Sev 'Debug'

        # ========================================================================
        # PHASE 2: Fetch all groups at once and filter in memory
        # ========================================================================
        # Fetch all groups in a single request, then create a lookup dictionary
        # for fast in-memory filtering when processing assignments
        # ========================================================================
        $GroupLookup = @{}  # Maps groupId -> group object

        try {
            # Fetch all groups at once (similar to Set-CIPPDBCacheGroups)
            $AllGroups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999&$select=id,displayName' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true

            # Handle case where response might be a single object instead of array
            if ($AllGroups -and -not ($AllGroups -is [System.Array])) {
                $AllGroups = @($AllGroups)
            }

            # Build lookup dictionary for O(1) access
            foreach ($Group in $AllGroups) {
                if ($Group.id) {
                    $GroupLookup[$Group.id] = $Group
                }
            }

            Write-LogMessage -Headers $Headers -API $APIName -message "Fetched $($AllGroups.Count) total groups, $($GroupLookup.Count) in lookup" -Sev 'Debug'
        } catch {
            Write-LogMessage -Headers $Headers -API $APIName -message "Could not fetch all groups: $($_.Exception.Message). Will use fallback for missing groups." -Sev 'Warning'
        }

        # ========================================================================
        # PHASE 3: Process all assignments using the group lookup
        # ========================================================================
        # Now that we have all groups, process each relationship's assignments
        # ========================================================================
        foreach ($Relationship in $Relationships) {
            $RelationshipId = $Relationship.id
            $RelationshipName = $Relationship.displayName
            $RelationshipStatus = $Relationship.status

            # Get assignments for this relationship
            if (-not $RelationshipAssignmentMap.ContainsKey($RelationshipId)) {
                # No assignments for this relationship, create empty groups list
                $AllRelationshipData.Add([PSCustomObject]@{
                    relationshipId      = $RelationshipId
                    relationshipName    = $RelationshipName
                    relationshipStatus  = $RelationshipStatus
                    customerTenantId    = $Relationship.customer.tenantId
                    customerTenantName  = $Relationship.customer.displayName
                    groups              = @()
                })
                continue
            }

            $AccessAssignments = $RelationshipAssignmentMap[$RelationshipId].Assignments
            $RelationshipGroups = [System.Collections.Generic.List[object]]::new()

            Write-LogMessage -Headers $Headers -API $APIName -message "Processing $($AccessAssignments.Count) access assignments for relationship ${RelationshipName}" -Sev 'Debug'

            foreach ($Assignment in $AccessAssignments) {
                # Extract the security group ID and roles from the assignment
                $GroupId = $null
                if ($Assignment.accessContainer) {
                    $GroupId = $Assignment.accessContainer.accessContainerId
                } elseif ($Assignment.value -and $Assignment.value.accessContainer) {
                    $GroupId = $Assignment.value.accessContainer.accessContainerId
                    $Assignment = $Assignment.value
                } else {
                    Write-LogMessage -Headers $Headers -API $APIName -message "Access assignment missing accessContainer: $($Assignment | ConvertTo-Json -Compress)" -Sev 'Warning'
                    continue
                }

                if ([string]::IsNullOrWhiteSpace($GroupId)) {
                    Write-LogMessage -Headers $Headers -API $APIName -message "Access assignment has empty accessContainerId: $($Assignment | ConvertTo-Json -Compress)" -Sev 'Warning'
                    continue
                }

                # Extract roles - handle both direct and nested structures
                $Roles = $null
                if ($Assignment.accessDetails -and $Assignment.accessDetails.unifiedRoles) {
                    $Roles = $Assignment.accessDetails.unifiedRoles
                } elseif ($Assignment.unifiedRoles) {
                    $Roles = $Assignment.unifiedRoles
                }

                if (-not $Roles -or $Roles.Count -eq 0) {
                    Write-LogMessage -Headers $Headers -API $APIName -message "Access assignment for group $GroupId has no roles assigned" -Sev 'Warning'
                    $Roles = @()
                }

                # Get group from lookup (already fetched all groups at once)
                $Group = $null
                if ($GroupLookup.ContainsKey($GroupId)) {
                    $Group = $GroupLookup[$GroupId]
                } else {
                    # Fallback: create minimal group object if not in lookup
                    # This can happen if the group was deleted or doesn't exist
                    $Group = [PSCustomObject]@{
                        id          = $GroupId
                        displayName = "Unknown Group ($GroupId)"
                    }
                    Write-LogMessage -Headers $Headers -API $APIName -message "Group $GroupId not found in lookup, using fallback" -Sev 'Warning'
                }

                # Process the assignment even if group lookup failed - we still have the group ID and roles
                if ($Group) {
                    # ================================================================
                    # Check if user is a member of this group (direct or nested)
                    # ================================================================
                    # We already have the user's transitive memberships, so we can
                    # quickly check if they're a member using our hashtable lookup.
                    # This is O(1) performance.
                    # ================================================================
                    $IsMember = $UserGroupMemberships.ContainsKey($GroupId)
                    $MembershipPath = @()
                    $IsPathComplete = $false

                    if ($IsMember) {
                        # ============================================================
                        # User IS a member (either direct or nested)
                        # ============================================================
                        # We know from transitiveMemberOf that the user is a member,
                        # but we need to determine if it's direct or nested, and if
                        # nested, try to find the path through intermediate groups.
                        # ============================================================
                        $IsPathComplete = $true
                        # Start with assumption of direct membership
                        $MembershipPath = @(
                            @{
                                groupId        = $GroupId
                                groupName      = $Group.displayName
                                membershipType = 'direct'
                            }
                        )

                        # ============================================================
                        # Determine if membership is direct or nested
                        # ============================================================
                        # We check the direct members of the group to see if the user
                        # is directly in it. If not, they must be nested (through
                        # another group that's a member of this group).
                        # ============================================================
                        try {
                            # Get direct members of the target group
                            $DirectMembers = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups/$GroupId/members?`$select=id,displayName,userPrincipalName" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true
                            $IsDirectMember = $DirectMembers.value | Where-Object { $_.id -eq $UserId }

                            if (-not $IsDirectMember) {
                                # ====================================================
                                # User is nested - find the path through nested groups
                                # ====================================================
                                # The user is not directly in this group, so they must
                                # be in a group that's a member of this group.
                                # We try to find which of the user's direct groups
                                # are members of this target group.
                                # ====================================================
                                $MembershipPath[0].membershipType = 'nested'

                                # Get groups the user is directly in (not nested)
                                $UserDirectGroups = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/users/$UserId/memberOf?`$select=id,displayName" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -ErrorAction SilentlyContinue
                                if ($UserDirectGroups) {
                                    $NestedGroups = @()
                                    # Check each of the user's direct groups
                                    foreach ($UserGroup in $UserDirectGroups) {
                                        if ($UserGroup.'@odata.type' -eq '#microsoft.graph.group') {
                                            try {
                                                # Check if this user's direct group is a member of the target group
                                                $GroupMembers = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups/$GroupId/members?`$select=id" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -ErrorAction SilentlyContinue
                                                if ($GroupMembers.value | Where-Object { $_.id -eq $UserGroup.id }) {
                                                    # Found it! This is the intermediate group
                                                    $NestedGroups += @{
                                                        groupId        = $UserGroup.id
                                                        groupName      = $UserGroup.displayName
                                                        membershipType = 'direct'  # User is direct member of this intermediate group
                                                    }
                                                }
                                            } catch {
                                                # Skip if we can't check (permissions issue, etc.)
                                            }
                                        }
                                    }
                                    if ($NestedGroups.Count -gt 0) {
                                        # Build the complete path: User → Intermediate Group → Target Group
                                        # Add the target group to complete the path
                                        $NestedGroups += @{
                                            groupId        = $GroupId
                                            groupName      = $Group.displayName
                                            membershipType = 'nested'  # Intermediate group is nested in target group
                                        }
                                        $MembershipPath = $NestedGroups
                                    }
                                }
                            }
                            # If IsDirectMember is true, membershipPath already shows 'direct' - we're done
                        } catch {
                            # If we can't check direct members (permissions, API error), assume nested
                            # This is a safe assumption - we know they're a member somehow
                            $MembershipPath[0].membershipType = 'nested'
                        }
                    } else {
                        # ============================================================
                        # User is NOT a member of this group
                        # ============================================================
                        # The group exists and has roles assigned, but the user isn't
                        # a member. This represents a broken path - the role is assigned
                        # but the user can't access it.
                        # ============================================================
                        # Check if the group has any members at all (for diagnostic purposes)
                        $GroupHasMembers = $false
                        try {
                            $GroupMembers = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups/$GroupId/members?`$top=1" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -ErrorAction SilentlyContinue
                            $GroupHasMembers = $GroupMembers.value.Count -gt 0
                        } catch {
                            $GroupHasMembers = $false
                        }

                        # Record the broken path
                        $MembershipPath = @(
                            @{
                                groupId         = $GroupId
                                groupName       = $Group.displayName
                                membershipType  = 'not_member'
                                groupHasMembers = $GroupHasMembers  # Helps diagnose if group is empty
                            }
                        )
                    }

                    # ================================================================
                    # Store group data for this relationship
                    # ================================================================
                    # We store all the information about this group including:
                    # - Whether user is a member
                    # - The membership path (direct/nested/not_member)
                    # - All roles assigned to this group
                    # ================================================================
                    $GroupData = [PSCustomObject]@{
                        groupId          = $GroupId
                        groupName        = $Group.displayName
                        roles            = $Roles  # Array of role objects with roleDefinitionId
                        isMember         = $IsMember
                        isPathComplete   = $IsPathComplete  # True if user can access this group
                        membershipPath   = $MembershipPath   # The path showing how user gets access (or why they don't)
                        assignmentStatus = $Assignment.status  # Status of the access assignment
                    }

                    $RelationshipGroups.Add($GroupData)
                    Write-LogMessage -Headers $Headers -API $APIName -message "Processed group $GroupDisplayName ($GroupId) with $($Roles.Count) roles for relationship ${RelationshipName}" -Sev 'Debug'

                    # ================================================================
                    # Map each role to this relationship/group combination
                    # ================================================================
                    # This builds our role-to-relationships map that we'll use later
                    # to check each of the 15 GDAP roles. For each role, we'll know:
                    # - Which relationships have it
                    # - Which groups in those relationships have it
                    # - Whether the user is a member of those groups
                    # ================================================================
                    if ($Roles -and $Roles.Count -gt 0) {
                        foreach ($Role in $Roles) {
                            # Handle both direct role objects and role objects with roleDefinitionId property
                            $RoleId = $null
                            if ($Role.roleDefinitionId) {
                                $RoleId = $Role.roleDefinitionId
                            } elseif ($Role -is [string]) {
                                $RoleId = $Role
                            } else {
                                Write-LogMessage -Headers $Headers -API $APIName -message "Role object missing roleDefinitionId: $($Role | ConvertTo-Json -Compress)" -Sev 'Warning'
                                continue
                            }

                            if ([string]::IsNullOrWhiteSpace($RoleId)) {
                                Write-LogMessage -Headers $Headers -API $APIName -message "Role has empty roleDefinitionId for group $GroupId" -Sev 'Warning'
                                continue
                            }

                            # Initialize list for this role if we haven't seen it before
                            if (-not $RoleToRelationshipsMap.ContainsKey($RoleId)) {
                                $RoleToRelationshipsMap[$RoleId] = [System.Collections.Generic.List[object]]::new()
                            }
                            # Add this relationship/group combination to the role's list
                            $RoleToRelationshipsMap[$RoleId].Add([PSCustomObject]@{
                                    relationshipId     = $RelationshipId
                                    relationshipName   = $RelationshipName
                                    relationshipStatus = $RelationshipStatus
                                    groupId            = $GroupId
                                    groupName          = $Group.displayName
                                    groupData          = $GroupData  # Full group data including membership info
                                })
                        }
                    }
                }
            }

            # Store relationship data for reference
            $AllRelationshipData.Add([PSCustomObject]@{
                    relationshipId    = $RelationshipId
                    relationshipName  = $RelationshipName
                    relationshipStatus = $RelationshipStatus
                    customerTenantId  = $Relationship.customer.tenantId
                    customerTenantName = $Relationship.customer.displayName
                    groups            = $RelationshipGroups
                })
        }

        # ============================================================================
        # STEP 7: Trace each of the 15 GDAP roles to the user
        # ============================================================================
        # This is the core logic - for each of the 15 standard GDAP roles, we:
        # 1. Find all relationships/groups that have this role assigned
        # 2. Check if the user is a member of any of those groups
        # 3. Build the complete access path showing how the user gets the role (if they do)
        # 4. Identify broken paths (role assigned but user not a member)
        #
        # The result is a role-centric view where each role shows:
        # - Whether it's assigned in any relationship
        # - Whether the user has access to it
        # - All relationships/groups that have it
        # - The complete path from role to user (if access exists)
        # ============================================================================
        $RoleTraces = [System.Collections.Generic.List[object]]::new()

        # Check each of the 15 standard GDAP roles
        foreach ($GDAPRole in $AllGDAPRoles) {
            $RoleId = $GDAPRole.Id
            $RoleName = $GDAPRole.Name
            $RoleDescription = $GDAPRole.Description

            # ========================================================================
            # Find all relationships/groups that have this role assigned
            # ========================================================================
            # We use the RoleToRelationshipsMap we built earlier. For each role,
            # this map contains all relationship/group combinations that have
            # this role assigned.
            # ========================================================================
            $RelationshipsWithRole = @()
            $UserHasAccess = $false
            $AccessPaths = [System.Collections.Generic.List[object]]::new()

            if ($RoleToRelationshipsMap.ContainsKey($RoleId)) {
                # This role exists in at least one relationship
                foreach ($RoleRelationship in $RoleToRelationshipsMap[$RoleId]) {
                    $GroupData = $RoleRelationship.groupData

                    # Record all relationships/groups that have this role (for reference)
                    $RelationshipsWithRole += [PSCustomObject]@{
                        relationshipId     = $RoleRelationship.relationshipId
                        relationshipName   = $RoleRelationship.relationshipName
                        relationshipStatus = $RoleRelationship.relationshipStatus
                        groupId            = $RoleRelationship.groupId
                        groupName          = $RoleRelationship.groupName
                        isUserMember       = $GroupData.isMember  # Whether user is in this group
                        membershipPath     = $GroupData.membershipPath  # How user gets access (or why they don't)
                    }

                    # ================================================================
                    # Check if user has access through this group
                    # ================================================================
                    # If the user is a member of this group (direct or nested),
                    # they have access to this role. We only need ONE path where
                    # the user is a member - if they're in any group with this role,
                    # they have access.
                    # ================================================================
                    if ($GroupData.isMember) {
                        $UserHasAccess = $true
                        # Record the access path for this role
                        $AccessPaths.Add([PSCustomObject]@{
                                relationshipId   = $RoleRelationship.relationshipId
                                relationshipName = $RoleRelationship.relationshipName
                                groupId          = $RoleRelationship.groupId
                                groupName        = $RoleRelationship.groupName
                                membershipPath   = $GroupData.membershipPath  # Shows: User → Group (or User → Intermediate → Group)
                            })
                    }
                }
            }

            # ========================================================================
            # Build the role trace object
            # ========================================================================
            # This contains all information about this role:
            # - roleExistsInRelationship: Role is available in at least one relationship (may not be assigned to any group)
            # - isAssigned: Role is assigned to at least one group (must exist in relationship first)
            # - isUserHasAccess: User is a member of at least one group with this role
            # - relationshipsWithRole: All relationships/groups that have this role assigned
            # - relationshipsWithRoleAvailable: All relationships where this role is available (but may not be assigned)
            # - accessPaths: Only the paths where user actually has access (if any)
            # ========================================================================
            $RoleExistsInRelationship = $RoleToAvailableRelationshipsMap.ContainsKey($RoleId)
            $IsAssigned = $RelationshipsWithRole.Count -gt 0

            # Get relationships where role is available but may not be assigned
            $RelationshipsWithRoleAvailable = @()
            if ($RoleToAvailableRelationshipsMap.ContainsKey($RoleId)) {
                $RelationshipsWithRoleAvailable = $RoleToAvailableRelationshipsMap[$RoleId]
            }

            $RoleTraces.Add([PSCustomObject]@{
                    roleName                      = $RoleName
                    roleId                        = $RoleId
                    roleDescription               = $RoleDescription
                    roleExistsInRelationship      = $RoleExistsInRelationship  # Role exists in at least one relationship
                    isAssigned                    = $IsAssigned  # Role is assigned to at least one group
                    isUserHasAccess                = $UserHasAccess
                    relationshipsWithRole          = $RelationshipsWithRole  # All places this role is assigned to groups
                    relationshipsWithRoleAvailable = $RelationshipsWithRoleAvailable  # All relationships where role is available
                    accessPaths                    = $AccessPaths  # Only paths where user has access
                })
        }

        # ============================================================================
        # STEP 8: Build final result structure - role-centric view
        # ============================================================================
        # The output is structured to be role-centric, making it easy to:
        # - See which of the 15 roles the user has access to
        # - See which roles are missing
        # - See the complete path for each role (if access exists)
        # - Identify broken paths (roles assigned but user not a member)
        #
        # The JSON structure is designed for diagram visualization, showing the
        # complete chain: Role → Relationship → Group → User (with nested groups)
        # ============================================================================

        # Calculate summary statistics
        $RolesWithAccess = ($RoleTraces | Where-Object { $_.isUserHasAccess -eq $true }).Count
        $RolesAssignedButNoAccess = ($RoleTraces | Where-Object { ($_.isAssigned -eq $true) -and ($_.isUserHasAccess -eq $false) }).Count
        $RolesInRelationshipButNotAssigned = ($RoleTraces | Where-Object { ($_.roleExistsInRelationship -eq $true) -and ($_.isAssigned -eq $false) }).Count
        $RolesNotInAnyRelationship = ($RoleTraces | Where-Object { $_.roleExistsInRelationship -eq $false }).Count

        # Build the results object with role-centric view
        $Results = [PSCustomObject]@{
            tenantId        = $CustomerTenantId
            tenantName      = $CustomerTenantName
            userUPN         = $UPN
            userId          = $UserId
            userDisplayName = $UserDisplayName
            roles           = $RoleTraces
            relationships   = $AllRelationshipData
            summary         = [PSCustomObject]@{
                totalRelationships              = $Relationships.Count
                totalRoles                      = $AllGDAPRoles.Count
                rolesWithAccess                 = $RolesWithAccess
                rolesAssignedButNoAccess         = $RolesAssignedButNoAccess
                rolesInRelationshipButNotAssigned = $RolesInRelationshipButNotAssigned
                rolesNotInAnyRelationship       = $RolesNotInAnyRelationship
            }
        }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Results
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Headers -API $APIName -message "Failed to test GDAP access path: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Error = $ErrorMessage.NormalizedError }
        }
    }
}
