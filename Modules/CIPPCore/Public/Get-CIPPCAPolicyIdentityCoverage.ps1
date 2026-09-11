function Get-CIPPCAPolicyIdentityCoverage {
    <#
    .SYNOPSIS
        Resolves who a Conditional Access policy's identity assignment touches, and why.
    .DESCRIPTION
        Returns touched users only (concrete include or exclude expansions). The All users token
        sets includesAllUsers and is not expanded into one row per directory user. Exclude wins
        for status; include+exclude rows stay in the result with both reason arrays.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$PolicyId
    )

    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $IncludeMap = @{}
    $ExcludeMap = @{}
    $Unresolved = [System.Collections.Generic.List[object]]::new()
    $IncludesAllUsers = $false
    $GroupNameLookup = @{}
    $RoleNameLookup = @{}

    function Add-CoverageReason {
        param (
            [hashtable]$Map,
            [string]$UserId,
            [hashtable]$Reason
        )
        if ([string]::IsNullOrWhiteSpace($UserId) -or $null -eq $Reason) { return }
        if (-not $Map.ContainsKey($UserId)) {
            $Map[$UserId] = [System.Collections.Generic.List[object]]::new()
        }
        $Existing = $Map[$UserId] | Where-Object { $_.value -eq $Reason.value }
        if ($Existing) { return }
        $Map[$UserId].Add([pscustomobject]$Reason) | Out-Null
    }

    function New-CoverageReason {
        param (
            [string]$Type,
            [string]$Id,
            [string]$Token,
            [string]$Label,
            [bool]$Transitive = $false,
            [string]$ViaGroupId,
            [string]$ViaGroupLabel
        )
        $ValueKey = if ($Id -and $ViaGroupId) {
            "$Type`:$Id`:group:$ViaGroupId"
        } elseif ($Id) {
            "$Type`:$Id"
        } elseif ($Token) {
            "$Type`:$Token"
        } else {
            $Type
        }
        $Reason = @{
            type  = $Type
            value = $ValueKey
            label = $Label
        }
        if ($Id) { $Reason.id = $Id }
        if ($Transitive) { $Reason.transitive = $true }
        if ($ViaGroupId) {
            $Reason.viaGroupId = $ViaGroupId
            if ($ViaGroupLabel) { $Reason.viaGroupLabel = $ViaGroupLabel }
        }
        return $Reason
    }

    function Test-IsGuid {
        param ([string]$Value)
        return $Value -match $GuidPattern
    }

    # Load policy
    $Policy = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/$PolicyId" -tenantid $TenantFilter -AsApp $true
    if (-not $Policy) {
        throw "Conditional Access policy $PolicyId was not found."
    }

    $Users = $Policy.conditions.users
    if ($null -eq $Users) {
        $Users = [pscustomobject]@{}
    }

    # --- Include / exclude users (GUIDs + tokens) ---
    foreach ($UserRef in @($Users.includeUsers)) {
        if ([string]::IsNullOrWhiteSpace($UserRef)) { continue }
        if ($UserRef -eq 'All') {
            $IncludesAllUsers = $true
            continue
        }
        if ($UserRef -eq 'None') { continue }
        if ($UserRef -eq 'GuestsOrExternalUsers') {
            try {
                $GuestUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,userType&`$top=999" -tenantid $TenantFilter -AsApp $true)
                foreach ($Guest in $GuestUsers) {
                    Add-CoverageReason -Map $IncludeMap -UserId $Guest.id -Reason (New-CoverageReason -Type 'includeUsers' -Token 'GuestsOrExternalUsers' -Label 'Guests or external users')
                }
            } catch {
                $Unresolved.Add([pscustomobject]@{ field = 'includeUsers'; id = 'GuestsOrExternalUsers'; error = $_.Exception.Message }) | Out-Null
            }
            continue
        }
        if (Test-IsGuid $UserRef) {
            Add-CoverageReason -Map $IncludeMap -UserId $UserRef -Reason (New-CoverageReason -Type 'includeUsers' -Id $UserRef -Label 'User inclusion')
        }
    }

    foreach ($UserRef in @($Users.excludeUsers)) {
        if ([string]::IsNullOrWhiteSpace($UserRef)) { continue }
        if ($UserRef -eq 'GuestsOrExternalUsers') {
            try {
                $GuestUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,userType&`$top=999" -tenantid $TenantFilter -AsApp $true)
                foreach ($Guest in $GuestUsers) {
                    Add-CoverageReason -Map $ExcludeMap -UserId $Guest.id -Reason (New-CoverageReason -Type 'excludeUsers' -Token 'GuestsOrExternalUsers' -Label 'Guests or external users')
                }
            } catch {
                $Unresolved.Add([pscustomobject]@{ field = 'excludeUsers'; id = 'GuestsOrExternalUsers'; error = $_.Exception.Message }) | Out-Null
            }
            continue
        }
        if (Test-IsGuid $UserRef) {
            Add-CoverageReason -Map $ExcludeMap -UserId $UserRef -Reason (New-CoverageReason -Type 'excludeUsers' -Id $UserRef -Label 'User exclusion')
        }
    }

    # --- Groups (transitive + direct, so nested can be labelled accurately) ---
    $IncludeGroups = @($Users.includeGroups | Where-Object { Test-IsGuid $_ })
    $ExcludeGroups = @($Users.excludeGroups | Where-Object { Test-IsGuid $_ })
    $AllGroupIds = @($IncludeGroups + $ExcludeGroups | Select-Object -Unique)

    if ($AllGroupIds.Count -gt 0) {
        $GroupDetailRequests = [System.Collections.Generic.List[object]]::new()
        $GroupMemberRequests = [System.Collections.Generic.List[object]]::new()
        foreach ($GroupId in $AllGroupIds) {
            $GroupDetailRequests.Add(@{
                    id     = "details-$GroupId"
                    method = 'GET'
                    url    = "groups/$GroupId`?`$select=id,displayName"
                })
            $GroupMemberRequests.Add(@{
                    id     = "transitive-$GroupId"
                    method = 'GET'
                    url    = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999"
                })
            $GroupMemberRequests.Add(@{
                    id     = "direct-$GroupId"
                    method = 'GET'
                    url    = "groups/$GroupId/members/microsoft.graph.user?`$select=id&`$top=999"
                })
        }

        try {
            $GroupDetailsResults = New-GraphBulkRequest -Requests @($GroupDetailRequests) -tenantid $TenantFilter -asapp $true
            foreach ($Result in @($GroupDetailsResults)) {
                $GroupId = $Result.id -replace '^details-', ''
                if ($Result.status -eq 200 -and $Result.body) {
                    $GroupNameLookup[$GroupId] = $Result.body.displayName
                } else {
                    $Field = if ($IncludeGroups -contains $GroupId) { 'includeGroups' } else { 'excludeGroups' }
                    $Unresolved.Add([pscustomobject]@{
                            field = $Field
                            id    = $GroupId
                            error = if ($Result.body.error.message) { $Result.body.error.message } else { "HTTP $($Result.status)" }
                        }) | Out-Null
                }
            }
        } catch {
            foreach ($GroupId in $AllGroupIds) {
                $Field = if ($IncludeGroups -contains $GroupId) { 'includeGroups' } else { 'excludeGroups' }
                $Unresolved.Add([pscustomobject]@{ field = $Field; id = $GroupId; error = $_.Exception.Message }) | Out-Null
            }
        }

        try {
            # New-GraphBulkRequest follows @odata.nextLink and merges pages into body.value
            $GroupMembersResults = New-GraphBulkRequest -Requests @($GroupMemberRequests) -tenantid $TenantFilter -asapp $true
            $DirectMembersByGroup = @{}
            $TransitiveMembersByGroup = @{}
            foreach ($Result in @($GroupMembersResults)) {
                if ($Result.status -ne 200) {
                    $FailedGroupId = if ($Result.id -like 'transitive-*') {
                        $Result.id -replace '^transitive-', ''
                    } elseif ($Result.id -like 'direct-*') {
                        $Result.id -replace '^direct-', ''
                    } else {
                        $null
                    }
                    # Transitive expansion is required for coverage; record once per group.
                    if ($Result.id -like 'transitive-*' -and $FailedGroupId) {
                        $Already = $Unresolved | Where-Object { $_.id -eq $FailedGroupId -and $_.field -like '*Groups' }
                        if (-not $Already) {
                            $Field = if ($IncludeGroups -contains $FailedGroupId) { 'includeGroups' } else { 'excludeGroups' }
                            $Unresolved.Add([pscustomobject]@{
                                    field = $Field
                                    id    = $FailedGroupId
                                    error = if ($Result.body.error.message) { $Result.body.error.message } else { "HTTP $($Result.status)" }
                                }) | Out-Null
                        }
                    }
                    continue
                }
                $MemberIds = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($Member in @($Result.body.value)) {
                    if ($Member.id) { [void]$MemberIds.Add([string]$Member.id) }
                }
                if ($Result.id -like 'direct-*') {
                    $DirectMembersByGroup[($Result.id -replace '^direct-', '')] = $MemberIds
                } elseif ($Result.id -like 'transitive-*') {
                    $TransitiveMembersByGroup[($Result.id -replace '^transitive-', '')] = $MemberIds
                }
            }

            foreach ($GroupId in $AllGroupIds) {
                if (-not $TransitiveMembersByGroup.ContainsKey($GroupId)) {
                    $Already = $Unresolved | Where-Object { $_.id -eq $GroupId -and $_.field -like '*Groups' }
                    if (-not $Already) {
                        $Field = if ($IncludeGroups -contains $GroupId) { 'includeGroups' } else { 'excludeGroups' }
                        $Unresolved.Add([pscustomobject]@{
                                field = $Field
                                id    = $GroupId
                                error = 'Group member expansion returned no result'
                            }) | Out-Null
                    }
                    continue
                }
                $Members = $TransitiveMembersByGroup[$GroupId]
                if (-not $Members) { continue }
                $DirectMembers = $DirectMembersByGroup[$GroupId]
                if (-not $DirectMembers) {
                    $DirectMembers = [System.Collections.Generic.HashSet[string]]::new()
                }

                $GroupLabel = if ($GroupNameLookup.ContainsKey($GroupId) -and $GroupNameLookup[$GroupId]) {
                    $GroupNameLookup[$GroupId]
                } else {
                    $GroupId
                }

                $IsInclude = $IncludeGroups -contains $GroupId
                $IsExclude = $ExcludeGroups -contains $GroupId
                foreach ($MemberId in $Members) {
                    $IsNested = -not $DirectMembers.Contains($MemberId)
                    $ReasonLabel = if ($IsNested) { "Group: $GroupLabel (nested)" } else { "Group: $GroupLabel" }
                    if ($IsInclude) {
                        Add-CoverageReason -Map $IncludeMap -UserId $MemberId -Reason (New-CoverageReason -Type 'includeGroups' -Id $GroupId -Label $ReasonLabel -Transitive $IsNested)
                    }
                    if ($IsExclude) {
                        Add-CoverageReason -Map $ExcludeMap -UserId $MemberId -Reason (New-CoverageReason -Type 'excludeGroups' -Id $GroupId -Label $ReasonLabel -Transitive $IsNested)
                    }
                }
            }
        } catch {
            foreach ($GroupId in $AllGroupIds) {
                $Already = $Unresolved | Where-Object { $_.id -eq $GroupId -and $_.field -like '*Groups' }
                if ($Already) { continue }
                $Field = if ($IncludeGroups -contains $GroupId) { 'includeGroups' } else { 'excludeGroups' }
                $Unresolved.Add([pscustomobject]@{
                        field = $Field
                        id    = $GroupId
                        error = "Group member expansion failed: $($_.Exception.Message)"
                    }) | Out-Null
            }
        }
    }

    # --- Roles (active assignments only) ---
    $IncludeRoles = @($Users.includeRoles | Where-Object { Test-IsGuid $_ })
    $ExcludeRoles = @($Users.excludeRoles | Where-Object { Test-IsGuid $_ })
    $AllRoleTemplateIds = @($IncludeRoles + $ExcludeRoles | Select-Object -Unique)

    if ($AllRoleTemplateIds.Count -gt 0) {
        $RoleDefinitions = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$select=id,templateId,displayName" -tenantid $TenantFilter -AsApp $true -ErrorAction SilentlyContinue)
        $TemplateToDefinitionId = @{}
        foreach ($Rd in $RoleDefinitions) {
            if ($null -ne $Rd.templateId) {
                $TemplateToDefinitionId[$Rd.templateId] = $Rd.id
                $RoleNameLookup[$Rd.templateId] = $Rd.displayName
                $RoleNameLookup[$Rd.id] = $Rd.displayName
            }
        }

        foreach ($RoleId in $AllRoleTemplateIds) {
            if (-not $RoleNameLookup.ContainsKey($RoleId) -and -not $TemplateToDefinitionId.ContainsKey($RoleId)) {
                $Field = if ($IncludeRoles -contains $RoleId) { 'includeRoles' } else { 'excludeRoles' }
                $Unresolved.Add([pscustomobject]@{ field = $Field; id = $RoleId; error = 'Role definition not found' }) | Out-Null
            }
        }

        $Assignments = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$expand=principal(`$select=id,displayName)" -tenantid $TenantFilter -AsApp $true -ErrorAction SilentlyContinue)

        # Group-held role assignments: expand transitive user members so CA role targeting matches Entra.
        $RoleGroupJobs = [System.Collections.Generic.List[object]]::new()
        foreach ($Assignment in $Assignments) {
            $PrincipalType = [string]$Assignment.principal.'@odata.type'
            if ($PrincipalType -ne '#microsoft.graph.group') { continue }
            $PrincipalId = $Assignment.principalId
            if (-not $PrincipalId) { continue }
            $DefId = $Assignment.roleDefinitionId

            foreach ($TemplateId in $AllRoleTemplateIds) {
                $MatchedDefId = $TemplateToDefinitionId[$TemplateId]
                if ($DefId -ne $MatchedDefId -and $DefId -ne $TemplateId) { continue }

                $RoleLabel = if ($RoleNameLookup.ContainsKey($TemplateId) -and $RoleNameLookup[$TemplateId]) {
                    $RoleNameLookup[$TemplateId]
                } else {
                    $TemplateId
                }
                $GroupLabel = if ($Assignment.principal.displayName) {
                    $Assignment.principal.displayName
                } else {
                    $PrincipalId
                }

                $RoleGroupJobs.Add([pscustomobject]@{
                        GroupId    = $PrincipalId
                        GroupLabel = $GroupLabel
                        TemplateId = $TemplateId
                        RoleLabel  = $RoleLabel
                        IsInclude  = ($IncludeRoles -contains $TemplateId)
                        IsExclude  = ($ExcludeRoles -contains $TemplateId)
                    }) | Out-Null
            }
        }

        $RoleGroupMemberLookup = @{}
        $UniqueRoleGroupIds = @($RoleGroupJobs.GroupId | Select-Object -Unique)
        if ($UniqueRoleGroupIds.Count -gt 0) {
            $RoleGroupMemberRequests = [System.Collections.Generic.List[object]]::new()
            foreach ($GroupId in $UniqueRoleGroupIds) {
                $RoleGroupMemberRequests.Add(@{
                        id     = "roleGroup-$GroupId"
                        method = 'GET'
                        url    = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999"
                    })
            }
            try {
                $RoleGroupMemberResults = New-GraphBulkRequest -Requests @($RoleGroupMemberRequests) -tenantid $TenantFilter -asapp $true
                foreach ($Result in @($RoleGroupMemberResults)) {
                    if ($Result.status -ne 200) { continue }
                    $GroupId = $Result.id -replace '^roleGroup-', ''
                    $MemberIds = [System.Collections.Generic.HashSet[string]]::new()
                    foreach ($Member in @($Result.body.value)) {
                        if ($Member.id) { [void]$MemberIds.Add([string]$Member.id) }
                    }
                    $RoleGroupMemberLookup[$GroupId] = $MemberIds
                }
            } catch {
                Write-Information "Get-CIPPCAPolicyIdentityCoverage: role-group member expansion failed: $($_.Exception.Message)"
            }
        }

        foreach ($Job in $RoleGroupJobs) {
            $Members = $RoleGroupMemberLookup[$Job.GroupId]
            if (-not $Members -or $Members.Count -eq 0) { continue }
            $ReasonLabel = "Role: $($Job.RoleLabel) via group $($Job.GroupLabel)"
            foreach ($MemberId in $Members) {
                if ($Job.IsInclude) {
                    Add-CoverageReason -Map $IncludeMap -UserId $MemberId -Reason (New-CoverageReason -Type 'includeRoles' -Id $Job.TemplateId -Label $ReasonLabel -ViaGroupId $Job.GroupId -ViaGroupLabel $Job.GroupLabel)
                }
                if ($Job.IsExclude) {
                    Add-CoverageReason -Map $ExcludeMap -UserId $MemberId -Reason (New-CoverageReason -Type 'excludeRoles' -Id $Job.TemplateId -Label $ReasonLabel -ViaGroupId $Job.GroupId -ViaGroupLabel $Job.GroupLabel)
                }
            }
        }

        foreach ($Assignment in $Assignments) {
            $PrincipalType = [string]$Assignment.principal.'@odata.type'
            if ($PrincipalType -and $PrincipalType -ne '#microsoft.graph.user') { continue }
            $PrincipalId = $Assignment.principalId
            if (-not $PrincipalId) { continue }
            $DefId = $Assignment.roleDefinitionId

            foreach ($TemplateId in $AllRoleTemplateIds) {
                $MatchedDefId = $TemplateToDefinitionId[$TemplateId]
                if ($DefId -ne $MatchedDefId -and $DefId -ne $TemplateId) { continue }

                $RoleLabel = if ($RoleNameLookup.ContainsKey($TemplateId) -and $RoleNameLookup[$TemplateId]) {
                    $RoleNameLookup[$TemplateId]
                } else {
                    $TemplateId
                }

                if ($IncludeRoles -contains $TemplateId) {
                    Add-CoverageReason -Map $IncludeMap -UserId $PrincipalId -Reason (New-CoverageReason -Type 'includeRoles' -Id $TemplateId -Label "Role: $RoleLabel")
                }
                if ($ExcludeRoles -contains $TemplateId) {
                    Add-CoverageReason -Map $ExcludeMap -UserId $PrincipalId -Reason (New-CoverageReason -Type 'excludeRoles' -Id $TemplateId -Label "Role: $RoleLabel")
                }
            }
        }
    }

    # --- Guests / external user blocks ---
    function Get-CoverageGuestHomeTenantId {
        param ($User)
        foreach ($Identity in @($User.identities)) {
            $Issuer = [string]$Identity.issuer
            if ($Issuer -match $GuidPattern) { return $Issuer }
        }
        return $null
    }

    function Get-CoverageGuestCategory {
        param ($User)
        $Upn = [string]$User.userPrincipalName
        $IsExt = $Upn -like '*#EXT#*'
        $UserType = [string]$User.userType
        if ($UserType -eq 'Guest' -and $IsExt) { return 'b2bCollaborationGuest' }
        if ($UserType -eq 'Member' -and $IsExt) { return 'b2bCollaborationMember' }
        if ($UserType -eq 'Guest' -and -not $IsExt) { return 'internalGuest' }
        return $null
    }

    function Test-CoverageExternalTenantMatch {
        param (
            $User,
            $ExternalTenants
        )
        if ($null -eq $ExternalTenants) { return $true }
        $Kind = [string]$ExternalTenants.membershipKind
        if ([string]::IsNullOrWhiteSpace($Kind) -or $Kind -eq 'all') { return $true }
        if ($Kind -ne 'enumerated') { return $true }

        $Allowed = @($ExternalTenants.members | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($Allowed.Count -eq 0) { return $false }

        $HomeTenantId = Get-CoverageGuestHomeTenantId -User $User
        if (-not $HomeTenantId) { return $false }
        return ($Allowed -contains $HomeTenantId)
    }

    function Expand-GuestBlock {
        param (
            $GuestConfig,
            [hashtable]$Map,
            [string]$Type,
            [string]$Field
        )
        if ($null -eq $GuestConfig) { return }
        $TypesRaw = $GuestConfig.guestOrExternalUserTypes
        if ([string]::IsNullOrWhiteSpace($TypesRaw) -or $TypesRaw -eq 'none') { return }

        $SelectedTypes = @(
            $TypesRaw -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -ne 'none' -and $_ -ne 'unknownFutureValue' } |
                Select-Object -Unique
        )
        if ($SelectedTypes.Count -eq 0) { return }

        # These CA categories are not reliably enumerable from directory user objects.
        $NonEnumerableTypes = @(
            'b2bDirectConnectUser'
            'otherExternalUser'
            'serviceProvider'
        )
        foreach ($GuestType in $SelectedTypes) {
            if ($NonEnumerableTypes -contains $GuestType) {
                $Unresolved.Add([pscustomobject]@{
                        field = $Field
                        id    = $GuestType
                        error = 'This guest or external user type cannot be expanded from directory users'
                    }) | Out-Null
            }
        }

        $EnumerableTypes = @(
            $SelectedTypes | Where-Object {
                $_ -in @('b2bCollaborationGuest', 'b2bCollaborationMember', 'internalGuest')
            }
        )
        if ($EnumerableTypes.Count -eq 0) { return }

        $Candidates = [System.Collections.Generic.List[object]]::new()
        try {
            if ($EnumerableTypes -contains 'b2bCollaborationGuest' -or $EnumerableTypes -contains 'internalGuest') {
                $GuestUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,userType,identities&`$top=999" -tenantid $TenantFilter -AsApp $true)
                foreach ($Guest in $GuestUsers) { $Candidates.Add($Guest) | Out-Null }
            }
            if ($EnumerableTypes -contains 'b2bCollaborationMember') {
                # B2B collaboration members keep the #EXT# UPN pattern with userType Member.
                $MemberExtUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$count=true&`$filter=userType eq 'Member' and contains(userPrincipalName,'#EXT#')&`$select=id,displayName,userPrincipalName,userType,identities&`$top=999" -tenantid $TenantFilter -AsApp $true -ComplexFilter)
                foreach ($Member in $MemberExtUsers) { $Candidates.Add($Member) | Out-Null }
            }
        } catch {
            $Unresolved.Add([pscustomobject]@{ field = $Field; id = $TypesRaw; error = $_.Exception.Message }) | Out-Null
            return
        }

        $Seen = [System.Collections.Generic.HashSet[string]]::new()
        $Label = "Guest types: $TypesRaw"
        foreach ($Candidate in $Candidates) {
            if (-not $Candidate.id) { continue }
            if (-not $Seen.Add([string]$Candidate.id)) { continue }

            $Category = Get-CoverageGuestCategory -User $Candidate
            if (-not $Category -or ($EnumerableTypes -notcontains $Category)) { continue }
            if (-not (Test-CoverageExternalTenantMatch -User $Candidate -ExternalTenants $GuestConfig.externalTenants)) {
                continue
            }

            Add-CoverageReason -Map $Map -UserId $Candidate.id -Reason (New-CoverageReason -Type $Type -Token $TypesRaw -Label $Label)
        }
    }

    Expand-GuestBlock -GuestConfig $Users.includeGuestsOrExternalUsers -Map $IncludeMap -Type 'includeGuestsOrExternalUsers' -Field 'includeGuestsOrExternalUsers'
    Expand-GuestBlock -GuestConfig $Users.excludeGuestsOrExternalUsers -Map $ExcludeMap -Type 'excludeGuestsOrExternalUsers' -Field 'excludeGuestsOrExternalUsers'

    # --- All token: annotate touched users only ---
    $AllReason = New-CoverageReason -Type 'includeUsers' -Token 'All' -Label 'All users'
    if ($IncludesAllUsers) {
        foreach ($UserId in @($IncludeMap.Keys + $ExcludeMap.Keys | Select-Object -Unique)) {
            Add-CoverageReason -Map $IncludeMap -UserId $UserId -Reason $AllReason
        }
    }

    # --- Union touched users and resolve directory labels ---
    $TouchedIds = @($IncludeMap.Keys + $ExcludeMap.Keys | Select-Object -Unique)
    $DirectoryLookup = @{}

    if ($TouchedIds.Count -gt 0) {
        for ($i = 0; $i -lt $TouchedIds.Count; $i += 1000) {
            $Batch = @($TouchedIds[$i..([Math]::Min($i + 999, $TouchedIds.Count - 1))])
            try {
                $Body = @{ ids = $Batch; types = @('user') }
                $Resolved = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName,userPrincipalName,userType' -tenantid $TenantFilter -body $Body -AsApp $true
                foreach ($Obj in @($Resolved.value)) {
                    if ($Obj.id) {
                        $DirectoryLookup[$Obj.id] = $Obj
                    }
                }
            } catch {
                Write-Information "Get-CIPPCAPolicyIdentityCoverage: getByIds failed: $($_.Exception.Message)"
            }
        }
    }

    # Mark assignment user GUIDs that never resolved
    foreach ($UserRef in @($Users.includeUsers + $Users.excludeUsers)) {
        if ((Test-IsGuid $UserRef) -and -not $DirectoryLookup.ContainsKey($UserRef)) {
            $Field = if (@($Users.includeUsers) -contains $UserRef) { 'includeUsers' } else { 'excludeUsers' }
            $Already = $Unresolved | Where-Object { $_.id -eq $UserRef -and $_.field -eq $Field }
            if (-not $Already) {
                $Unresolved.Add([pscustomobject]@{ field = $Field; id = $UserRef; error = 'User not found' }) | Out-Null
            }
        }
    }

    $Identities = [System.Collections.Generic.List[object]]::new()
    foreach ($UserId in ($TouchedIds | Sort-Object)) {
        $IncludeReasons = if ($IncludeMap.ContainsKey($UserId)) { @($IncludeMap[$UserId]) } else { @() }
        $ExcludeReasons = if ($ExcludeMap.ContainsKey($UserId)) { @($ExcludeMap[$UserId]) } else { @() }

        $Status = if ($ExcludeReasons.Count -gt 0) { 'excluded' } else { 'covered' }
        $Dir = $DirectoryLookup[$UserId]

        $Identities.Add([pscustomobject]@{
                id                = $UserId
                displayName       = if ($Dir.displayName) { $Dir.displayName } else { $UserId }
                userPrincipalName = if ($Dir.userPrincipalName) { $Dir.userPrincipalName } else { $null }
                userType          = if ($Dir.userType) { $Dir.userType } else { $null }
                status            = $Status
                includeReasons    = @($IncludeReasons)
                excludeReasons    = @($ExcludeReasons)
            }) | Out-Null
    }

    $CoveredCount = @($Identities | Where-Object { $_.status -eq 'covered' }).Count
    $ExcludedCount = @($Identities | Where-Object { $_.status -eq 'excluded' }).Count

    $HasExcludeUsers = @($Users.excludeUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
    $HasExcludeGroups = @($Users.excludeGroups | Where-Object { Test-IsGuid $_ }).Count -gt 0
    $HasExcludeRoles = @($Users.excludeRoles | Where-Object { Test-IsGuid $_ }).Count -gt 0
    $HasExcludeGuests = $null -ne $Users.excludeGuestsOrExternalUsers -and
        -not [string]::IsNullOrWhiteSpace($Users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes) -and
        $Users.excludeGuestsOrExternalUsers.guestOrExternalUserTypes -ne 'none'
    $HasExclusions = $HasExcludeUsers -or $HasExcludeGroups -or $HasExcludeRoles -or $HasExcludeGuests

    return [pscustomobject]@{
        policyId         = $Policy.id
        displayName      = $Policy.displayName
        state            = $Policy.state
        includesAllUsers = [bool]$IncludesAllUsers
        hasExclusions    = [bool]$HasExclusions
        summary          = [pscustomobject]@{
            coveredCount    = $CoveredCount
            excludedCount   = $ExcludedCount
            unresolvedCount = $Unresolved.Count
            touchedCount    = $Identities.Count
        }
        unresolved       = @($Unresolved)
        identities       = @($Identities)
    }
}
