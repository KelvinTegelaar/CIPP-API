function Push-DBCacheOneDriveRootPermissionsBatch {
    <#
    .SYNOPSIS
        Collects OneDrive root permissions for a batch of personal sites.

    .DESCRIPTION
        Processes up to 20 personal site seeds per activity. Each site is wrapped in its own
        try/catch so a batch of N sites always returns exactly N cache row objects.

        Six permission paths are indexed into permissionsJson (a pre-serialized JSON string):
        SiteAdmin, SiteRoleGroup, WebRoleAssignment, LibraryRoleAssignment, DriveRootGrant,
        DriveRootLink. Groups are stored as principals and are not expanded to users.

        collectionStatus:
        - Full     — all SPO REST paths and Graph drive root permissions succeeded
        - Skipped  — drive/owner resolution failed, SPO or Graph collection failed, or unexpected error;
                      permissionsJson = '[]'. Push-StoreOneDriveRootPermissions may replace Skipped rows
                      with prior Full cache data (merge-on-Skip) before the tenant write.

        hasNonStandardAccess is nullable ($true | $false | $null). Use -eq $true / -eq $false;
        never truthy checks. $null on batch Skipped rows; after merge-on-Skip at store, merged sites
        retain prior hasNonStandardAccess from the cached Full row.

        Test-IsOwnerPrincipal compares grants to the provisioned owner (drive.owner.user.id):
        principalObjectId match, principalUpn -ieq, or LoginName claim suffix -ieq owner UPN.

        Dedup inside permissionsJson:
        - WebRoleAssignment: skip Member.Id matching associated Owner/Member/Visitor group Ids
        - LibraryRoleAssignment: only when HasUniqueRoleAssignments is true
        - DriveRootGrant: skip siteGroup.displayName matching associated group Title (case-insensitive);
          skip implicit owner grant (roles contains 'owner' + Test-IsOwnerPrincipal)
        - Intentional cross-path duplicates remain (e.g. same user on SiteAdmin and SiteRoleGroup)

        Graph root permissions: skip inheritedFrom; paginate via New-GraphGetRequest; DriveRootGrant
        and named DriveRootLink recipients emit one grant per person; anonymous DriveRootLink
        emits one grant per permission.id.

        Anonymous DriveRootLink shape: principalType=Link, sharedWith=@(), linkScope/linkType populated.

        Consumer notes:
        - Grant paths != effective access (security groups need Entra membership join)
        - Unprovisioned OneDrives absent from getAllSites
        - Batch Skipped rows have permissionsJson = '[]' and hasNonStandardAccess $null; after store,
          merge-on-Skip may replace them with prior Full rows — query the cache, not batch output
        - Count DriveRootLink sharing links by distinct permissionId, not grant row count (named
          recipients share the same permissionId across multiple grant rows)
        - Child folder/file sharing is out of scope (SharePointSharingLinks cache)
        - Localized/renamed group titles may miss siteGroup dedup (grant retained, warning logged)

        Never uses User Information List fallback.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $BatchNumber = $Item.BatchNumber
    $SiteSeeds = @($Item.Sites)

    # Returns $true when a SharePoint user entity is a guest/external identity.
    function Test-SPGuestUser {
        param($User)
        [bool]$User.IsShareByEmailGuestUser -or [bool]$User.IsEmailAuthenticationGuestUser -or
            ($User.LoginName -match '(?i)#ext#|urn%3aspo%3aguest')
    }

    # Compares a grant principal to the provisioned OneDrive owner (drive.owner).
    function Test-IsOwnerPrincipal {
        param($Grant, $OwnerObjectId, $OwnerPrincipalName)
        if ($OwnerObjectId -and $Grant.principalObjectId -and
            $Grant.principalObjectId -eq $OwnerObjectId) { return $true }
        if ($OwnerPrincipalName -and $Grant.principalUpn -and
            $Grant.principalUpn -ieq $OwnerPrincipalName) { return $true }
        if ($OwnerPrincipalName -and $Grant.principalLoginName -and
            ($Grant.principalLoginName -split '\|')[-1] -ieq $OwnerPrincipalName) { return $true }
        return $false
    }

    function Get-CIPPSpoPrincipalType {
        param($Entity)
        if ($Entity.LoginName -match '(?i)federateddirectoryclaimprovider') { return 'M365 Group' }
        switch ($Entity.PrincipalType) {
            1 { 'User' }
            4 { 'Security Group' }
            8 { 'SharePoint Group' }
            default { 'Other' }
        }
    }

    function Get-CIPPSpoUserUpn {
        param($User)
        if ($User.PrincipalType -eq 1 -and $User.LoginName) {
            return ($User.LoginName -split '\|')[-1]
        }
        $null
    }

    function New-CIPPSpoUserGrant {
        param(
            $User,
            [string]$PermissionSource,
            [string]$Group,
            $RoleBinding = $null,
            [bool]$IsSiteAdmin = $false,
            [string]$LibraryTitle = $null
        )
        [PSCustomObject]@{
            permissionSource     = $PermissionSource
            group                = $Group
            principalId          = [string]$User.Id
            principalObjectId    = $null
            principalUpn         = Get-CIPPSpoUserUpn -User $User
            principalDisplayName = $User.Title
            principalLoginName   = $User.LoginName
            principalEmail       = $User.Email
            principalType        = Get-CIPPSpoPrincipalType -Entity $User
            permissionLevel      = if ($RoleBinding) { $RoleBinding.Name } else { $null }
            roleDefinitionId     = if ($RoleBinding) { $RoleBinding.Id } else { $null }
            roles                = @()
            isSiteAdmin          = $IsSiteAdmin
            isGuest              = (Test-SPGuestUser -User $User)
            permissionId         = $null
            linkScope            = $null
            linkType             = $null
            linkUrl              = $null
            hasPassword          = $null
            expirationDateTime   = $null
            sharedWith           = @()
            libraryTitle         = $LibraryTitle
        }
    }

    function New-CIPPSpoRoleAssignmentGrant {
        param($Member, $RoleBinding, [string]$PermissionSource, [string]$LibraryTitle = $null)
        $principalUpn = if ($Member.PrincipalType -eq 1 -and $Member.LoginName) {
            ($Member.LoginName -split '\|')[-1]
        } else { $null }
        [PSCustomObject]@{
            permissionSource     = $PermissionSource
            group                = $RoleBinding.Name
            principalId          = [string]$Member.Id
            principalObjectId    = $null
            principalUpn         = $principalUpn
            principalDisplayName = $Member.Title
            principalLoginName   = $Member.LoginName
            principalEmail       = $Member.Email
            principalType        = Get-CIPPSpoPrincipalType -Entity $Member
            permissionLevel      = $RoleBinding.Name
            roleDefinitionId     = $RoleBinding.Id
            roles                = @()
            isSiteAdmin          = $false
            isGuest              = (Test-SPGuestUser -User $Member)
            permissionId         = $null
            linkScope            = $null
            linkType             = $null
            linkUrl              = $null
            hasPassword          = $null
            expirationDateTime   = $null
            sharedWith           = @()
            libraryTitle         = $LibraryTitle
        }
    }

    function Get-CIPPGraphIdentityLabel {
        param($Identity)
        $Identity.user.email ?? $Identity.user.userPrincipalName ??
            $Identity.siteUser.email ?? $Identity.user.displayName ??
            $Identity.siteUser.displayName ?? $Identity.group.email ??
            $Identity.group.displayName ?? $Identity.siteGroup.displayName ??
            $Identity.application.displayName
    }

    function Test-CIPPGraphGuestIdentity {
        param($Identity)
        $LoginName = [string]($Identity.siteUser.loginName ?? $Identity.user.loginName ?? '')
        if ($LoginName -match '(?i)#ext#|urn%3aspo%3aguest|urn:spo:guest') { return $true }
        $Email = [string]($Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? '')
        $Email -match '(?i)#EXT#'
    }

    function New-CIPPGraphIdentityGrant {
        param(
            $Identity,
            [string]$PermissionSource,
            [string]$PermissionId,
            [array]$Roles,
            [array]$SharedWith,
            $LinkProps = $null
        )
        $principalType = 'Other'
        $principalObjectId = $null
        $principalUpn = $null
        $principalDisplayName = $null
        $principalLoginName = $null
        $principalEmail = $null
        $principalId = $null

        if ($Identity.user) {
            $principalType = 'User'
            $principalObjectId = $Identity.user.id
            $principalUpn = $Identity.user.userPrincipalName ?? $Identity.user.email
            $principalDisplayName = $Identity.user.displayName
            $principalEmail = $Identity.user.email ?? $Identity.user.userPrincipalName
            $principalId = [string]($Identity.user.id ?? $principalUpn)
        } elseif ($Identity.siteUser) {
            $principalType = 'User'
            $principalLoginName = $Identity.siteUser.loginName
            $principalDisplayName = $Identity.siteUser.displayName
            $principalEmail = $Identity.siteUser.email
            $principalUpn = if ($principalLoginName) { ($principalLoginName -split '\|')[-1] } else { $null }
            $principalId = [string]($principalLoginName ?? $principalEmail ?? $principalDisplayName)
        } elseif ($Identity.group) {
            $principalType = 'Security Group'
            $principalObjectId = $Identity.group.id
            $principalDisplayName = $Identity.group.displayName
            $principalEmail = $Identity.group.email
            $principalId = [string]$Identity.group.id
        } elseif ($Identity.siteGroup) {
            $principalType = 'SharePoint Group'
            $principalDisplayName = $Identity.siteGroup.displayName
            $principalId = [string]($Identity.siteGroup.id ?? $Identity.siteGroup.displayName)
        } elseif ($Identity.application) {
            $principalType = 'Application'
            $principalDisplayName = $Identity.application.displayName
            $principalId = [string]$Identity.application.id
        }

        $grant = [PSCustomObject]@{
            permissionSource     = $PermissionSource
            group                = $null
            principalId          = $principalId
            principalObjectId    = $principalObjectId
            principalUpn         = $principalUpn
            principalDisplayName = $principalDisplayName
            principalLoginName   = $principalLoginName
            principalEmail       = $principalEmail
            principalType        = $principalType
            permissionLevel      = $null
            roleDefinitionId     = $null
            roles                = @($Roles)
            isSiteAdmin          = $false
            isGuest              = (Test-CIPPGraphGuestIdentity -Identity $Identity)
            permissionId         = $PermissionId
            linkScope            = $null
            linkType             = $null
            linkUrl              = $null
            hasPassword          = $null
            expirationDateTime   = $null
            sharedWith           = @($SharedWith)
            libraryTitle         = $null
        }

        if ($LinkProps) {
            $grant.linkScope = $LinkProps.linkScope
            $grant.linkType = $LinkProps.linkType
            $grant.linkUrl = $LinkProps.linkUrl
            $grant.hasPassword = $LinkProps.hasPassword
            $grant.expirationDateTime = $LinkProps.expirationDateTime
            $grant.principalType = 'Link'
        }

        $grant
    }

    function Get-CIPPHasNonStandardAccess {
        param($Grants, $OwnerObjectId, $OwnerPrincipalName, $LibraryHasUniquePermissions, $CollectionStatus)
        if ($CollectionStatus -eq 'Skipped') { return $null }
        if ($LibraryHasUniquePermissions) { return $true }

        foreach ($Grant in $Grants) {
            if ($Grant.permissionSource -eq 'SiteAdmin' -and -not (Test-IsOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
                return $true
            }
            if ($Grant.permissionSource -eq 'SiteRoleGroup' -and $Grant.group -in @('Members', 'Visitors')) {
                return $true
            }
            if ($Grant.permissionSource -eq 'SiteRoleGroup' -and $Grant.group -eq 'Owners' -and
                -not (Test-IsOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
                return $true
            }
            if ($Grant.principalType -in @('Security Group', 'M365 Group', 'SharePoint Group')) {
                return $true
            }
            if ($Grant.isGuest) { return $true }
            if ($Grant.permissionSource -eq 'DriveRootLink') { return $true }
            if ($Grant.permissionSource -eq 'DriveRootGrant' -and
                -not (Test-IsOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
                return $true
            }
            if ($Grant.permissionSource -in @('WebRoleAssignment', 'LibraryRoleAssignment') -and
                -not (Test-IsOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
                return $true
            }
        }
        return $false
    }

    function New-CIPPSkippedSiteRow {
        param($SiteSeed, $CollectionError)
        [PSCustomObject]@{
            id                          = $SiteSeed.id
            siteId                      = $SiteSeed.id
            siteUrl                     = $SiteSeed.webUrl
            siteDisplayName             = $SiteSeed.displayName
            ownerPrincipalName          = $null
            ownerObjectId               = $null
            ownerDisplayName            = $null
            driveId                     = $null
            driveWebUrl                 = $null
            libraryId                   = $null
            libraryHasUniquePermissions = $false
            collectionStatus            = 'Skipped'
            collectionError             = $CollectionError
            hasNonStandardAccess        = $null
            permissionsJson             = '[]'
            grantCount                  = 0
            collectedAt                 = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    function Get-CIPPOneDriveSiteRow {
        param($SiteSeed, $TenantFilter)

        $SiteId = $SiteSeed.id
        $SiteUrl = $SiteSeed.webUrl
        $SiteDisplayName = $SiteSeed.displayName
        $CollectedAt = (Get-Date).ToUniversalTime().ToString('o')

        $Drive = $null
        try {
            $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drive?`$select=id,owner,webUrl,sharepointIds" -tenantid $TenantFilter -asapp $true
        } catch {
            return (New-CIPPSkippedSiteRow -SiteSeed $SiteSeed -CollectionError "Drive resolution failed: $($_.Exception.Message)")
        }

        if (-not $Drive -or -not $Drive.id) {
            return (New-CIPPSkippedSiteRow -SiteSeed $SiteSeed -CollectionError 'Drive resolution returned no drive')
        }

        $OwnerObjectId = $Drive.owner.user.id
        $OwnerDisplayName = $Drive.owner.user.displayName
        $OwnerPrincipalName = $Drive.owner.user.userPrincipalName ?? $Drive.owner.user.email
        if (-not $OwnerPrincipalName -and $OwnerObjectId) {
            try {
                $OwnerUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$OwnerObjectId?`$select=userPrincipalName" -tenantid $TenantFilter -asapp $true
                $OwnerPrincipalName = $OwnerUser.userPrincipalName
            } catch {
                $OwnerPrincipalName = $null
            }
        }

        $DriveId = $Drive.id
        $DriveWebUrl = $Drive.webUrl
        $LibraryId = $Drive.sharepointIds.listId
        $LibraryHasUniquePermissions = $false
        $LibraryTitle = $null

        $SpoGrants = [System.Collections.Generic.List[object]]::new()
        $AssociatedGroupIds = [System.Collections.Generic.HashSet[string]]::new()
        $AssociatedGroupTitles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        try {
            $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
            $Scope = "$($SharePointInfo.SharePointUrl)/.default"
            $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
            $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

            $AssociatedEndpoints = [ordered]@{
                'Owners'   = 'associatedownergroup'
                'Members'  = 'associatedmembergroup'
                'Visitors' = 'associatedvisitorgroup'
            }
            foreach ($RoleName in $AssociatedEndpoints.Keys) {
                $GroupEntity = New-GraphGetRequest -uri "$BaseUri/web/$($AssociatedEndpoints[$RoleName])?`$select=Id,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                if ($GroupEntity.Id) {
                    [void]$AssociatedGroupIds.Add([string]$GroupEntity.Id)
                    if ($GroupEntity.Title) { [void]$AssociatedGroupTitles.Add([string]$GroupEntity.Title) }
                }
            }

            $SiteAdmins = @(New-GraphGetRequest -uri "$BaseUri/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,Email,LoginName,PrincipalType,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
            foreach ($Admin in $SiteAdmins) {
                $SpoGrants.Add((New-CIPPSpoUserGrant -User $Admin -PermissionSource 'SiteAdmin' -Group 'Site Admins' -IsSiteAdmin $true))
            }

            foreach ($RoleName in $AssociatedEndpoints.Keys) {
                $Users = @(New-GraphGetRequest -uri "$BaseUri/web/$($AssociatedEndpoints[$RoleName])/users?`$select=Id,Title,Email,LoginName,PrincipalType,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                foreach ($User in $Users) {
                    $SpoGrants.Add((New-CIPPSpoUserGrant -User $User -PermissionSource 'SiteRoleGroup' -Group $RoleName))
                }
            }

            $WebAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
            foreach ($Assignment in $WebAssignments) {
                if ($Assignment.Member.Id -and $AssociatedGroupIds.Contains([string]$Assignment.Member.Id)) { continue }
                foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                    $SpoGrants.Add((New-CIPPSpoRoleAssignmentGrant -Member $Assignment.Member -RoleBinding $Binding -PermissionSource 'WebRoleAssignment'))
                }
            }

            if ($LibraryId) {
                $ListInfo = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$LibraryId')?`$select=HasUniqueRoleAssignments,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                $LibraryHasUniquePermissions = [bool]$ListInfo.HasUniqueRoleAssignments
                $LibraryTitle = $ListInfo.Title
                if ($LibraryHasUniquePermissions) {
                    $LibraryAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$LibraryId')/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                    foreach ($Assignment in $LibraryAssignments) {
                        if ($Assignment.Member.Id -and $AssociatedGroupIds.Contains([string]$Assignment.Member.Id)) { continue }
                        foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                            $SpoGrants.Add((New-CIPPSpoRoleAssignmentGrant -Member $Assignment.Member -RoleBinding $Binding -PermissionSource 'LibraryRoleAssignment' -LibraryTitle $LibraryTitle))
                        }
                    }
                }
            }

        } catch {
            $SpoError = $_.Exception.Message
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: SPO collection failed for '$SiteUrl': $SpoError" -sev Warning
            return (New-CIPPSkippedSiteRow -SiteSeed $SiteSeed -CollectionError "SPO collection failed: $SpoError")
        }

        $GraphGrants = [System.Collections.Generic.List[object]]::new()
        $InheritedSkipCount = 0
        try {
            $Permissions = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drive/root/permissions" -tenantid $TenantFilter -asapp $true)
            foreach ($Permission in $Permissions) {
                if ($Permission.inheritedFrom) {
                    $InheritedSkipCount++
                    continue
                }

                if ($Permission.link) {
                    $Recipients = @($Permission.grantedToIdentitiesV2 ?? $Permission.grantedToIdentities ?? @())
                    $SharedWith = @($Recipients | ForEach-Object { Get-CIPPGraphIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)
                    $LinkProps = @{
                        linkScope          = $Permission.link.scope ?? 'users'
                        linkType           = $Permission.link.type ?? 'view'
                        linkUrl            = $Permission.link.webUrl
                        hasPassword        = [bool]($Permission.hasPassword ?? $false)
                        expirationDateTime = $Permission.expirationDateTime
                    }
                    if ($Recipients.Count -eq 0) {
                        $GraphGrants.Add([PSCustomObject]@{
                                permissionSource     = 'DriveRootLink'
                                group                = $null
                                principalId          = [string]$Permission.id
                                principalObjectId    = $null
                                principalUpn         = $null
                                principalDisplayName = $null
                                principalLoginName   = $null
                                principalEmail       = $null
                                principalType        = 'Link'
                                permissionLevel      = $null
                                roleDefinitionId     = $null
                                roles                = @($Permission.roles)
                                isSiteAdmin          = $false
                                isGuest              = $false
                                permissionId         = [string]$Permission.id
                                linkScope            = $LinkProps.linkScope
                                linkType             = $LinkProps.linkType
                                linkUrl              = $LinkProps.linkUrl
                                hasPassword          = $LinkProps.hasPassword
                                expirationDateTime   = $LinkProps.expirationDateTime
                                sharedWith           = @()
                                libraryTitle         = $null
                            })
                    } else {
                        foreach ($Recipient in $Recipients) {
                            $GraphGrants.Add((New-CIPPGraphIdentityGrant -Identity $Recipient -PermissionSource 'DriveRootLink' -PermissionId $Permission.id -Roles @($Permission.roles) -SharedWith $SharedWith -LinkProps $LinkProps))
                        }
                    }
                    continue
                }

                $Recipients = @($Permission.grantedToIdentitiesV2 ?? @())
                if ($Recipients.Count -eq 0 -and $Permission.grantedToV2) {
                    $Recipients = @($Permission.grantedToV2)
                }
                if ($Recipients.Count -eq 0) { continue }

                $SharedWith = @($Recipients | ForEach-Object { Get-CIPPGraphIdentityLabel -Identity $_ } | Where-Object { $_ } | Sort-Object -Unique)
                foreach ($Recipient in $Recipients) {
                    if ($Recipient.siteGroup -and $Recipient.siteGroup.displayName -and
                        $AssociatedGroupTitles.Contains([string]$Recipient.siteGroup.displayName)) {
                        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: siteGroup dedup matched '$($Recipient.siteGroup.displayName)' on '$SiteUrl'" -sev Debug
                        continue
                    }
                    $Candidate = New-CIPPGraphIdentityGrant -Identity $Recipient -PermissionSource 'DriveRootGrant' -PermissionId $Permission.id -Roles @($Permission.roles) -SharedWith $SharedWith
                    if ($Permission.roles -contains 'owner' -and
                        (Test-IsOwnerPrincipal -Grant $Candidate -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
                        continue
                    }
                    $GraphGrants.Add($Candidate)
                }
            }
            if ($InheritedSkipCount -gt 0) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: skipped $InheritedSkipCount inherited root permissions on '$SiteUrl'" -sev Debug
            }
        } catch {
            return (New-CIPPSkippedSiteRow -SiteSeed $SiteSeed -CollectionError "Graph root permissions failed: $($_.Exception.Message)")
        }

        $AllGrants = @($SpoGrants) + @($GraphGrants)

        $HasNonStandardAccess = Get-CIPPHasNonStandardAccess -Grants $AllGrants -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName -LibraryHasUniquePermissions $LibraryHasUniquePermissions -CollectionStatus 'Full'
        $PermissionsJson = if ($AllGrants.Count -gt 0) {
            ConvertTo-Json -InputObject @($AllGrants) -Compress -Depth 10
        } else {
            '[]'
        }

        [PSCustomObject]@{
            id                          = $SiteId
            siteId                      = $SiteId
            siteUrl                     = $SiteUrl
            siteDisplayName             = $SiteDisplayName
            ownerPrincipalName          = $OwnerPrincipalName
            ownerObjectId               = $OwnerObjectId
            ownerDisplayName            = $OwnerDisplayName
            driveId                     = $DriveId
            driveWebUrl                 = $DriveWebUrl
            libraryId                   = $LibraryId
            libraryHasUniquePermissions = $LibraryHasUniquePermissions
            collectionStatus            = 'Full'
            collectionError             = $null
            hasNonStandardAccess        = $HasNonStandardAccess
            permissionsJson             = $PermissionsJson
            grantCount                  = $AllGrants.Count
            collectedAt                 = $CollectedAt
        }
    }

    $SiteRows = [System.Collections.Generic.List[object]]::new()

    try {
        Write-Information "Processing OneDrive root permissions batch $BatchNumber for tenant $TenantFilter with $($SiteSeeds.Count) sites"

        foreach ($SiteSeed in $SiteSeeds) {
            try {
                $SiteRows.Add((Get-CIPPOneDriveSiteRow -SiteSeed $SiteSeed -TenantFilter $TenantFilter))
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root permissions: unexpected site error for '$($SiteSeed.webUrl)': $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
                $SiteRows.Add((New-CIPPSkippedSiteRow -SiteSeed $SiteSeed -CollectionError $_.Exception.Message))
            }
        }

        if ($SiteRows.Count -ne $SiteSeeds.Count) {
            throw "Batch $BatchNumber invariant violated: expected $($SiteSeeds.Count) site rows, got $($SiteRows.Count)"
        }

        return [PSCustomObject]@{
            BatchNumber = $BatchNumber
            Sites       = @($SiteRows)
        }

    } catch {
        $ErrorMsg = "Failed OneDrive root permissions batch $BatchNumber for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
