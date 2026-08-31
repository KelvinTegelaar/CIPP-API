function Invoke-ListSiteBrowserPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Extensive permission inventory for a SharePoint site or library for the site browser.
        Collects SPO site admins, associated Owners/Members/Visitors (with members), all site
        groups (with members), web/library role assignments, and Graph site permissions
        (Sites.Selected / app-only grants). Partial failures are returned in Errors so the UI
        can still show what was collected. SiteUrl is required; ListId targets a library.
        Sharing links / Graph drive permissions are intentionally out of scope (handled elsewhere).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.TenantFilter ?? $Request.Query.tenantFilter ?? $Request.Body.TenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl
    $SiteId = $Request.Query.SiteId ?? $Request.Body.SiteId
    $ListId = $Request.Query.ListId ?? $Request.Body.ListId

    function Test-SPGuestPrincipal {
        param($Principal)
        [bool]$Principal.IsShareByEmailGuestUser -or
        [bool]$Principal.IsEmailAuthenticationGuestUser -or
        ($Principal.LoginName -match '(?i)#ext#|urn%3aspo%3aguest')
    }

    function ConvertTo-PrincipalTypeName {
        param($PrincipalType)
        switch ($PrincipalType) {
            1 { 'User' }
            2 { 'Distribution List' }
            4 { 'Security Group' }
            8 { 'SharePoint Group' }
            default { 'Other' }
        }
    }

    function ConvertTo-PrincipalObject {
        param($Member)
        if (-not $Member) { return $null }
        [PSCustomObject]@{
            principalId       = [string]$Member.Id
            title             = $Member.Title
            loginName         = $Member.LoginName
            email             = $Member.Email
            userPrincipalName = if ($Member.PrincipalType -eq 1 -and $Member.LoginName) { ($Member.LoginName -split '\|')[-1] } else { $null }
            principalType     = ConvertTo-PrincipalTypeName -PrincipalType $Member.PrincipalType
            principalTypeId   = $Member.PrincipalType
            isGuest           = (Test-SPGuestPrincipal $Member)
            isSiteAdmin       = [bool]$Member.IsSiteAdmin
        }
    }

    function ConvertTo-RoleAssignmentRows {
        param(
            $Assignments,
            [string]$Source,
            $SystemGroupIds = $null,
            $SystemGroupLoginNames = $null
        )
        # One row per principal; multiple RoleDefinitionBindings become permissionLevels[].
        $ByPrincipal = [ordered]@{}
        foreach ($Assignment in @($Assignments)) {
            $Member = $Assignment.Member
            if (-not $Member) { continue }
            $Principal = ConvertTo-PrincipalObject -Member $Member
            $Key = [string]$Principal.principalId
            if (-not $ByPrincipal.Contains($Key)) {
                $ByPrincipal[$Key] = [PSCustomObject]@{
                    source            = $Source
                    principalId       = $Principal.principalId
                    title             = $Principal.title
                    loginName         = $Principal.loginName
                    email             = $Principal.email
                    userPrincipalName = $Principal.userPrincipalName
                    principalType     = $Principal.principalType
                    isGuest           = $Principal.isGuest
                    permissionLevels  = [System.Collections.Generic.List[object]]::new()
                }
            }
            $SeenIds = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Existing in @($ByPrincipal[$Key].permissionLevels)) {
                [void]$SeenIds.Add([string]$Existing.roleDefinitionId)
            }
            foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                $RoleId = [string]$Binding.Id
                if ($SeenIds.Contains($RoleId)) { continue }
                [void]$SeenIds.Add($RoleId)
                $ByPrincipal[$Key].permissionLevels.Add([PSCustomObject]@{
                        name             = $Binding.Name
                        roleDefinitionId = $RoleId
                        roleTypeKind     = $Binding.RoleTypeKind
                        description      = $Binding.Description
                        isSystemManaged  = ($Binding.RoleTypeKind -eq 1)
                    })
            }
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Key in @($ByPrincipal.Keys)) {
            $Row = $ByPrincipal[$Key]
            $Levels = @($Row.permissionLevels)
            # Prefer a non-system level for the primary label; keep all in permissionLevels.
            $Primary = @($Levels | Where-Object { -not $_.isSystemManaged } | Select-Object -First 1)
            if (-not $Primary) { $Primary = @($Levels | Select-Object -First 1) }
            $IsSystemGroup = $false
            if ($null -ne $SystemGroupIds -and $Row.principalId) {
                $IsSystemGroup = [bool]$SystemGroupIds.Contains([string]$Row.principalId)
            }
            if (-not $IsSystemGroup -and $null -ne $SystemGroupLoginNames -and $Row.loginName) {
                $IsSystemGroup = [bool]$SystemGroupLoginNames.Contains([string]$Row.loginName)
            }
            $Rows.Add([PSCustomObject]@{
                    source             = $Row.source
                    principalId        = $Row.principalId
                    title              = $Row.title
                    loginName          = $Row.loginName
                    email              = $Row.email
                    userPrincipalName  = $Row.userPrincipalName
                    principalType      = $Row.principalType
                    isGuest            = $Row.isGuest
                    permissionLevel    = if ($Primary) { $Primary[0].name } else { $null }
                    roleDefinitionId   = if ($Primary) { $Primary[0].roleDefinitionId } else { $null }
                    roleTypeKind       = if ($Primary) { $Primary[0].roleTypeKind } else { $null }
                    description        = if ($Primary) { $Primary[0].description } else { $null }
                    isSystemManaged    = [bool](@($Levels | Where-Object { $_.isSystemManaged }).Count -eq $Levels.Count -and $Levels.Count -gt 0)
                    hasSystemManaged   = [bool](@($Levels | Where-Object { $_.isSystemManaged }).Count)
                    isSystemGroup      = $IsSystemGroup
                    permissionLevels   = $Levels
                })
        }
        return @($Rows)
    }

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = 'tenantFilter is required.' }
            })
    }
    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{'Results' = 'SiteUrl is required.' }
            })
    }

    $Errors = [System.Collections.Generic.List[object]]::new()
    $IsLibrary = -not [string]::IsNullOrWhiteSpace($ListId)

    try {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $SpoScope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        # --- Target / inheritance ---
        $TargetTitle = $null
        $HasUniqueRoleAssignments = $true
        if ($IsLibrary) {
            try {
                $ListInfo = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$ListId')?`$select=HasUniqueRoleAssignments,Title,Id" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                $TargetTitle = $ListInfo.Title
                # [bool]$null is $false — that hides "Fix inheritance" when the property is not
                # projected. Probe the scalar endpoint before treating the library as inheriting.
                $HasUniqueRaw = $ListInfo.HasUniqueRoleAssignments
                if ($null -eq $HasUniqueRaw) {
                    try {
                        $Probe = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$ListId')/HasUniqueRoleAssignments" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                        $HasUniqueRaw = if ($null -ne $Probe.PSObject.Properties['value']) { $Probe.value } else { $Probe }
                    } catch {
                        $HasUniqueRaw = $null
                    }
                }
                $HasUniqueRoleAssignments = $HasUniqueRaw -eq $true -or "$HasUniqueRaw" -eq 'true'
            } catch {
                $Errors.Add([PSCustomObject]@{ section = 'target'; message = $_.Exception.Message })
            }
        } else {
            try {
                $WebInfo = New-GraphGetRequest -uri "$BaseUri/web?`$select=Title,HasUniqueRoleAssignments,Id" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                $TargetTitle = $WebInfo.Title
                $HasUniqueRoleAssignments = $true
            } catch {
                $Errors.Add([PSCustomObject]@{ section = 'target'; message = $_.Exception.Message })
            }
        }

        # --- Site collection admins ---
        $SiteAdmins = @()
        try {
            $AdminUsers = @(New-GraphGetRequest -uri "$BaseUri/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,Email,LoginName,PrincipalType,IsSiteAdmin,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
            $SiteAdmins = @($AdminUsers | ForEach-Object { ConvertTo-PrincipalObject -Member $_ })
        } catch {
            $Errors.Add([PSCustomObject]@{ section = 'siteAdmins'; message = $_.Exception.Message })
        }

        # --- Associated Owners / Members / Visitors ---
        $AssociatedGroups = [System.Collections.Generic.List[object]]::new()
        $AssociatedEndpoints = [ordered]@{
            'Owners'   = 'associatedownergroup'
            'Members'  = 'associatedmembergroup'
            'Visitors' = 'associatedvisitorgroup'
        }
        foreach ($RoleName in $AssociatedEndpoints.Keys) {
            try {
                $GroupEntity = New-GraphGetRequest -uri "$BaseUri/web/$($AssociatedEndpoints[$RoleName])?`$select=Id,Title,LoginName,Description,OwnerTitle,OnlyAllowMembersViewMembership" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                $Members = @()
                if ($GroupEntity.Id) {
                    try {
                        $Users = @(New-GraphGetRequest -uri "$BaseUri/web/$($AssociatedEndpoints[$RoleName])/users?`$select=Id,Title,Email,LoginName,PrincipalType,IsSiteAdmin,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                        $Members = @($Users | ForEach-Object { ConvertTo-PrincipalObject -Member $_ })
                    } catch {
                        $Errors.Add([PSCustomObject]@{ section = "associatedGroups.$RoleName.members"; message = $_.Exception.Message })
                    }
                }
                $AssociatedGroups.Add([PSCustomObject]@{
                        role          = $RoleName
                        groupId       = [string]$GroupEntity.Id
                        title         = $GroupEntity.Title
                        loginName     = $GroupEntity.LoginName
                        description   = $GroupEntity.Description
                        ownerTitle    = $GroupEntity.OwnerTitle
                        memberCount   = $Members.Count
                        members       = $Members
                        isSystemGroup = $true
                    })
            } catch {
                $Errors.Add([PSCustomObject]@{ section = "associatedGroups.$RoleName"; message = $_.Exception.Message })
            }
        }

        $SystemGroupIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $SystemGroupLoginNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($Associated in $AssociatedGroups) {
            if (-not [string]::IsNullOrWhiteSpace($Associated.groupId)) {
                [void]$SystemGroupIds.Add([string]$Associated.groupId)
            }
            if (-not [string]::IsNullOrWhiteSpace($Associated.loginName)) {
                [void]$SystemGroupLoginNames.Add([string]$Associated.loginName)
            }
        }

        # --- All SharePoint groups + members ---
        $SharePointGroups = [System.Collections.Generic.List[object]]::new()
        try {
            $Groups = @(New-GraphGetRequest -uri "$BaseUri/web/sitegroups?`$select=Id,Title,LoginName,Description,OwnerTitle,OnlyAllowMembersViewMembership,AllowMembersEditMembership,RequestToJoinLeaveEmailSetting" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
            foreach ($Group in $Groups) {
                $Members = @()
                try {
                    $Users = @(New-GraphGetRequest -uri "$BaseUri/web/sitegroups($($Group.Id))/users?`$select=Id,Title,Email,LoginName,PrincipalType,IsSiteAdmin,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                    $Members = @($Users | ForEach-Object { ConvertTo-PrincipalObject -Member $_ })
                } catch {
                    $Errors.Add([PSCustomObject]@{ section = "sharePointGroups.$($Group.Id).members"; message = $_.Exception.Message })
                }
                $GroupId = [string]$Group.Id
                $SharePointGroups.Add([PSCustomObject]@{
                        groupId                        = $GroupId
                        title                          = $Group.Title
                        loginName                      = $Group.LoginName
                        description                    = $Group.Description
                        ownerTitle                     = $Group.OwnerTitle
                        onlyAllowMembersViewMembership = [bool]$Group.OnlyAllowMembersViewMembership
                        allowMembersEditMembership     = [bool]$Group.AllowMembersEditMembership
                        memberCount                    = $Members.Count
                        members                        = $Members
                        isSystemGroup                  = $SystemGroupIds.Contains($GroupId)
                    })
            }
        } catch {
            $Errors.Add([PSCustomObject]@{ section = 'sharePointGroups'; message = $_.Exception.Message })
        }

        # --- Role assignments (web always; library when ListId and unique) ---
        $WebRoleAssignments = @()
        try {
            $WebAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
            $WebRoleAssignments = ConvertTo-RoleAssignmentRows -Assignments $WebAssignments -Source 'WebRoleAssignment' -SystemGroupIds $SystemGroupIds -SystemGroupLoginNames $SystemGroupLoginNames
        } catch {
            $Errors.Add([PSCustomObject]@{ section = 'webRoleAssignments'; message = $_.Exception.Message })
        }

        $LibraryRoleAssignments = @()
        if ($IsLibrary) {
            if ($HasUniqueRoleAssignments) {
                try {
                    $LibraryAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$ListId')/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $SpoScope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                    $LibraryRoleAssignments = ConvertTo-RoleAssignmentRows -Assignments $LibraryAssignments -Source 'LibraryRoleAssignment' -SystemGroupIds $SystemGroupIds -SystemGroupLoginNames $SystemGroupLoginNames
                } catch {
                    $Errors.Add([PSCustomObject]@{ section = 'libraryRoleAssignments'; message = $_.Exception.Message })
                }
            }
        }

        # --- Graph site permissions (Sites.Selected / app-only grants; site-scoped) ---
        $GraphSitePermissions = @()
        $ResolvedSiteId = $SiteId
        try {
            if ([string]::IsNullOrWhiteSpace($ResolvedSiteId)) {
                $ParsedUrl = [System.Uri]$SiteUrl
                $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
                    $ParsedUrl.Host
                } else {
                    "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
                }
                $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment`?`$select=id" -tenantid $TenantFilter -asapp $true
                $ResolvedSiteId = $SiteMeta.id
            }
            if ([string]::IsNullOrWhiteSpace($ResolvedSiteId)) {
                throw 'Could not resolve Graph site id.'
            }
            $RawGraphPerms = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$ResolvedSiteId/permissions" -tenantid $TenantFilter -asapp $true)
            $GraphSitePermissions = foreach ($Perm in $RawGraphPerms) {
                $IdentitySets = @($Perm.grantedToIdentitiesV2)
                if ($IdentitySets.Count -eq 0) { $IdentitySets = @($Perm.grantedToIdentities) }
                if ($IdentitySets.Count -eq 0 -and $Perm.grantedToV2) { $IdentitySets = @($Perm.grantedToV2) }
                if ($IdentitySets.Count -eq 0 -and $Perm.grantedTo) { $IdentitySets = @($Perm.grantedTo) }

                $Identities = foreach ($Set in $IdentitySets) {
                    if ($Set.application) {
                        [PSCustomObject]@{
                            type        = 'application'
                            id          = [string]$Set.application.id
                            displayName = $Set.application.displayName
                        }
                    } elseif ($Set.user) {
                        [PSCustomObject]@{
                            type        = 'user'
                            id          = [string]$Set.user.id
                            displayName = $Set.user.displayName
                        }
                    } elseif ($Set.group) {
                        [PSCustomObject]@{
                            type        = 'group'
                            id          = [string]$Set.group.id
                            displayName = $Set.group.displayName
                        }
                    }
                }
                $Identities = @($Identities)
                $Primary = $Identities | Select-Object -First 1
                [PSCustomObject]@{
                    permissionId  = [string]$Perm.id
                    roles         = @($Perm.roles)
                    identities    = $Identities
                    title         = if ($Primary) { $Primary.displayName } else { $null }
                    identityType  = if ($Primary) { $Primary.type } else { $null }
                    identityId    = if ($Primary) { $Primary.id } else { $null }
                    link          = if ($Perm.link) { $true } else { $false }
                }
            }
            # Sharing-link shaped Graph permissions belong elsewhere; keep app/user/group grants only.
            $GraphSitePermissions = @($GraphSitePermissions | Where-Object {
                    -not $_.link -and (@($_.identities).Count -gt 0)
                })
        } catch {
            $Errors.Add([PSCustomObject]@{ section = 'graphSitePermissions'; message = $_.Exception.Message })
        }

        $Body = [PSCustomObject]@{
            target = [PSCustomObject]@{
                type                     = if ($IsLibrary) { 'library' } else { 'site' }
                title                    = $TargetTitle
                siteUrl                  = $SiteUrl
                siteId                   = $ResolvedSiteId
                listId                   = if ($IsLibrary) { $ListId } else { $null }
                hasUniqueRoleAssignments = $HasUniqueRoleAssignments
                inheritsFromSite         = $IsLibrary -and -not $HasUniqueRoleAssignments
            }
            siteAdmins             = @($SiteAdmins)
            associatedGroups       = @($AssociatedGroups)
            sharePointGroups       = @($SharePointGroups)
            webRoleAssignments     = @($WebRoleAssignments)
            libraryRoleAssignments = @($LibraryRoleAssignments)
            graphSitePermissions   = @($GraphSitePermissions)
            errors                 = @($Errors)
            collectedAt            = (Get-Date).ToUniversalTime().ToString('o')
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list site browser permissions: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Body -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Body }
        })
}
