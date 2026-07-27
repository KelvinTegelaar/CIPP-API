function Push-DBCacheSharePointPermissionsBatch {
    <#
    .SYNOPSIS
        Collects site and document library permissions for a batch of SharePoint sites.

    .DESCRIPTION
        Processes up to 20 site seeds per activity via the SharePoint REST API with certificate
        authentication. Each site is wrapped in its own try/catch so a batch of N sites always
        returns exactly N site results - Push-StoreSharePointPermissions relies on that to verify
        completeness before it replaces the cache.

        Per site: the root web role assignments, then the visible document libraries. Only
        libraries that hold their own permissions (HasUniqueRoleAssignments) are read - a library
        that still inherits has exactly the site's permissions, so storing them would fill the
        cache with rows carrying no information. Cache size therefore tracks governance drift
        rather than tenant size.

        Two row types are emitted, discriminated by rowType:
        - Site       one per scanned site, always exactly one whether collection succeeded or not.
                     Carries collectionStatus, the library counts and the error when Skipped.
        - Assignment one per scope, principal and permission level. A principal holding several
                     levels on the same scope produces one row per level, because each is granted
                     and removed separately.

        A library with unique permissions but no assignments (possible after breaking inheritance
        without copying) still emits one Assignment row with null principal fields, so it is not
        silently missing from the library inventory.

        broadClaim flags the tenant-wide claims SharePoint exposes as well-known login names -
        Everyone, Everyone except external users, and All Users. These are the oversharing
        footgun this scan exists to surface.

        collectionStatus:
        - Full     the root web and every library that needed reading were collected
        - Skipped  SPO REST collection failed for the site; no assignment rows are emitted.
                   Push-StoreSharePointPermissions may restore this site's rows from the prior
                   cache (merge-on-Skip) before the tenant write.

        Consumer notes:
        - Grant paths are not effective access: security groups are stored as principals and are
          not expanded to their members
        - Libraries that inherit are absent by design; their permissions are the site's
        - Folder and file level permissions are out of scope (that would cost a full tree walk)

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $BatchNumber = $Item.BatchNumber
    $SiteSeeds = @($Item.Sites)

    # Returns $true when a SharePoint principal is a guest/external identity.
    function Test-SPGuestPrincipal {
        param($Principal)
        [bool]$Principal.IsShareByEmailGuestUser -or [bool]$Principal.IsEmailAuthenticationGuestUser -or
            ($Principal.LoginName -match '(?i)#ext#|urn%3aspo%3aguest')
    }

    function Get-SPPrincipalType {
        param($Entity)
        if ($Entity.LoginName -match '(?i)federateddirectoryclaimprovider') { return 'M365 Group' }
        switch ($Entity.PrincipalType) {
            1 { 'User' }
            4 { 'Security Group' }
            8 { 'SharePoint Group' }
            default { 'Other' }
        }
    }

    # SharePoint expresses tenant-wide audiences as well-known claim login names. -like is used
    # rather than -match because these contain regex metacharacters ( | ! ).
    function Get-SPBroadClaim {
        param([string]$LoginName)
        if ([string]::IsNullOrWhiteSpace($LoginName)) { return $null }
        if ($LoginName -like 'c:0(.s|true*') { return 'Everyone' }
        if ($LoginName -like '*spo-grid-all-users*') { return 'EveryoneExceptExternal' }
        if ($LoginName -like 'c:0!.s|windows*') { return 'AllUsers' }
        return $null
    }

    # Flattens one roleassignments response into Assignment rows for a scope.
    function ConvertTo-AssignmentRow {
        param($Assignments, $Site, [string]$Scope, $Library, [string]$CollectedAt)

        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Assignment in @($Assignments)) {
            $Member = $Assignment.Member
            if (-not $Member) { continue }
            $BroadClaim = Get-SPBroadClaim -LoginName ([string]$Member.LoginName)
            foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                $Rows.Add([PSCustomObject]@{
                        rowType           = 'Assignment'
                        id                = "$($Site.SiteId)_$($Library.Id ?? 'root')_$($Member.Id)_$($Binding.Id)"
                        siteId            = $Site.SiteId
                        siteName          = $Site.SiteName
                        siteUrl           = $Site.SiteUrl
                        scope             = $Scope
                        libraryId         = $Library.Id
                        libraryTitle      = $Library.Title
                        libraryUrl        = $Library.Url
                        principalId       = [string]$Member.Id
                        title             = $Member.Title
                        loginName         = $Member.LoginName
                        email             = $Member.Email
                        userPrincipalName = if ($Member.PrincipalType -eq 1 -and $Member.LoginName) { ($Member.LoginName -split '\|')[-1] } else { $null }
                        principalType     = Get-SPPrincipalType -Entity $Member
                        isGuest           = (Test-SPGuestPrincipal $Member)
                        permissionLevel   = $Binding.Name
                        roleDefinitionId  = [string]$Binding.Id
                        isSystemManaged   = ($Binding.RoleTypeKind -eq 1)
                        broadClaim        = $BroadClaim
                        # Boolean companion to broadClaim: the three claim types share no common
                        # substring, so a table filter needs a single field to match on.
                        isTenantWide      = [bool]$BroadClaim
                        collectedAt       = $CollectedAt
                    })
            }
        }
        return $Rows
    }

    function New-SiteRow {
        param($SiteSeed, [string]$Status, [string]$ErrorMessage, [int]$LibrariesScanned, [int]$LibrariesUnique, [string]$CollectedAt)
        [PSCustomObject]@{
            rowType                        = 'Site'
            id                             = "$($SiteSeed.id)_site"
            siteId                         = $SiteSeed.id
            siteName                       = $SiteSeed.displayName
            siteUrl                        = $SiteSeed.webUrl
            collectionStatus               = $Status
            collectionError                = $ErrorMessage
            librariesScanned               = $LibrariesScanned
            librariesWithUniquePermissions = $LibrariesUnique
            collectedAt                    = $CollectedAt
        }
    }

    $SiteResults = [System.Collections.Generic.List[object]]::new()

    try {
        Write-Information "Processing SharePoint permissions batch $BatchNumber for tenant $TenantFilter with $($SiteSeeds.Count) sites"

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }

        foreach ($SiteSeed in $SiteSeeds) {
            $CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
            $Rows = [System.Collections.Generic.List[object]]::new()
            try {
                $BaseUri = "$($SiteSeed.webUrl.TrimEnd('/'))/_api"
                $SiteContext = [PSCustomObject]@{
                    SiteId   = $SiteSeed.id
                    SiteName = $SiteSeed.displayName
                    SiteUrl  = $SiteSeed.webUrl
                }
                $NoLibrary = [PSCustomObject]@{ Id = $null; Title = $null; Url = $null }

                # 1) Root web assignments.
                $WebAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                foreach ($Row in (ConvertTo-AssignmentRow -Assignments $WebAssignments -Site $SiteContext -Scope 'Site' -Library $NoLibrary -CollectedAt $CollectedAt)) {
                    $Rows.Add($Row)
                }

                # 2) Document libraries. BaseTemplate 101 is a document library, 119 the Site Pages
                #    library - the same pair Invoke-ListSiteLibraries surfaces through Graph.
                $Lists = @(New-GraphGetRequest -uri "$BaseUri/web/lists?`$select=Id,Title,Hidden,BaseTemplate,HasUniqueRoleAssignments,RootFolder/ServerRelativeUrl&`$expand=RootFolder" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                $Libraries = @($Lists | Where-Object { $_.Hidden -ne $true -and $_.BaseTemplate -in @(101, 119) })

                $UniqueCount = 0
                foreach ($Library in $Libraries) {
                    # $select should project HasUniqueRoleAssignments across the collection. If it
                    # comes back null the property was not projected, so fall back to reading it
                    # per library - one extra call each, the scan stays proportional to libraries.
                    $HasUnique = $Library.HasUniqueRoleAssignments
                    if ($null -eq $HasUnique) {
                        Write-Information "SharePoint permissions: HasUniqueRoleAssignments not projected on the lists collection for '$($SiteSeed.webUrl)', falling back to a per-library check"
                        $ListInfo = New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$($Library.Id)')?`$select=HasUniqueRoleAssignments" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                        $HasUnique = $ListInfo.HasUniqueRoleAssignments
                    }
                    if ($HasUnique -ne $true) { continue }

                    $UniqueCount++
                    $LibraryContext = [PSCustomObject]@{
                        Id    = [string]$Library.Id
                        Title = $Library.Title
                        Url   = $Library.RootFolder.ServerRelativeUrl
                    }
                    $LibraryAssignments = @(New-GraphGetRequest -uri "$BaseUri/web/lists(guid'$($Library.Id)')/roleassignments?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true)
                    $LibraryRows = ConvertTo-AssignmentRow -Assignments $LibraryAssignments -Site $SiteContext -Scope 'Library' -Library $LibraryContext -CollectedAt $CollectedAt
                    foreach ($Row in $LibraryRows) { $Rows.Add($Row) }

                    # Unique permissions but nothing granted: keep the library visible in the
                    # inventory rather than letting it vanish from the counts.
                    if ($LibraryRows.Count -eq 0) {
                        $Rows.Add([PSCustomObject]@{
                                rowType           = 'Assignment'
                                id                = "$($SiteSeed.id)_$($Library.Id)_empty"
                                siteId            = $SiteSeed.id
                                siteName          = $SiteSeed.displayName
                                siteUrl           = $SiteSeed.webUrl
                                scope             = 'Library'
                                libraryId         = $LibraryContext.Id
                                libraryTitle      = $LibraryContext.Title
                                libraryUrl        = $LibraryContext.Url
                                principalId       = $null
                                title             = $null
                                loginName         = $null
                                email             = $null
                                userPrincipalName = $null
                                principalType     = $null
                                isGuest           = $false
                                permissionLevel   = $null
                                roleDefinitionId  = $null
                                isSystemManaged   = $false
                                broadClaim        = $null
                                isTenantWide      = $false
                                collectedAt       = $CollectedAt
                            })
                    }
                }

                $SiteResults.Add([PSCustomObject]@{
                        SiteId           = $SiteSeed.id
                        CollectionStatus = 'Full'
                        SiteRow          = (New-SiteRow -SiteSeed $SiteSeed -Status 'Full' -ErrorMessage $null -LibrariesScanned $Libraries.Count -LibrariesUnique $UniqueCount -CollectedAt $CollectedAt)
                        Rows             = @($Rows)
                    })

            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SharePoint permissions: collection failed for '$($SiteSeed.webUrl)': $($_.Exception.Message)" -sev Warning
                $SiteResults.Add([PSCustomObject]@{
                        SiteId           = $SiteSeed.id
                        CollectionStatus = 'Skipped'
                        SiteRow          = (New-SiteRow -SiteSeed $SiteSeed -Status 'Skipped' -ErrorMessage $_.Exception.Message -LibrariesScanned 0 -LibrariesUnique 0 -CollectedAt $CollectedAt)
                        Rows             = @()
                    })
            }
        }

        if ($SiteResults.Count -ne $SiteSeeds.Count) {
            throw "Batch $BatchNumber invariant violated: expected $($SiteSeeds.Count) site results, got $($SiteResults.Count)"
        }

        return [PSCustomObject]@{
            BatchNumber = $BatchNumber
            Sites       = @($SiteResults)
        }

    } catch {
        $ErrorMsg = "Failed SharePoint permissions batch $BatchNumber for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
