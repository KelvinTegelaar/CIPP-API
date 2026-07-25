function Invoke-ListSiteUserAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Explains how one user can reach a SharePoint site or document library: every route that
        grants them access, and the permission level each route carries. This is the effective
        access answer that the permission lists cannot give on their own, because those show who
        holds a grant rather than who the grant resolves to.

        Routes checked, live:
        - Site collection administrator (full control over everything in the site)
        - A permission granted straight to the user
        - Membership of a SharePoint group that holds a permission, including the Owners,
          Members and Visitors groups
        - Membership of an Entra security group or Microsoft 365 group that holds a permission,
          resolved through transitiveMemberOf so nested groups count
        - A tenant-wide claim (Everyone, Everyone except external users, All Users), which every
          internal user matches
        - Sharing links and direct item shares the user received, read from the
          SharePointSharingLinks cache rather than live

        When a library is given and it still inherits, its permissions are the site's, so the
        site is evaluated and the result says so.

        Limited Access is reported but flagged, because on its own it grants no ability to open
        or list anything - SharePoint adds it so a user can traverse to an item they were given
        access to further down.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SiteUrl = $Request.Query.SiteUrl ?? $Request.Body.SiteUrl
    $ListId = $Request.Query.ListId ?? $Request.Body.ListId
    $UserPrincipalName = $Request.Query.UserPrincipalName ?? $Request.Body.UserPrincipalName

    try {
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }
        if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) { throw 'UserPrincipalName is required.' }

        # --- Resolve the user and every group they are in, nested groups included ---
        $User = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UserPrincipalName`?`$select=id,displayName,userPrincipalName,mail,userType" -tenantid $TenantFilter -AsApp $true
        if (-not $User.id) { throw "User $UserPrincipalName was not found in this tenant." }
        $IsGuest = $User.userType -eq 'Guest' -or $User.userPrincipalName -match '(?i)#ext#'

        $GroupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $GroupNameById = @{}
        try {
            $Memberships = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($User.id)/transitiveMemberOf?`$select=id,displayName&`$top=999" -tenantid $TenantFilter -AsApp $true)
            foreach ($Membership in $Memberships) {
                if ($Membership.id) {
                    [void]$GroupIds.Add([string]$Membership.id)
                    $GroupNameById[[string]$Membership.id] = $Membership.displayName
                }
            }
        } catch {
            Write-Information "Could not read group membership for $UserPrincipalName : $($_.Exception.Message)"
        }

        # --- SharePoint scope ---
        $SPScope = Resolve-CIPPSharePointPermissionScope -SiteUrl $SiteUrl -ListId $ListId -TenantFilter $TenantFilter
        $Inherits = $SPScope.IsLibrary -and -not $SPScope.HasUniqueRoleAssignments
        # An inheriting library has no assignments of its own; the site's apply instead.
        $AssignmentUri = if ($Inherits) { "$($SPScope.BaseUri)/web/roleassignments" } else { $SPScope.AssignmentUri }

        $Paths = [System.Collections.Generic.List[object]]::new()

        # Matches a role assignment principal against the user, returning how it matched.
        function Get-PrincipalMatch {
            param($Member, $User, $GroupIds, $GroupNameById)

            $LoginName = [string]$Member.LoginName

            # Tenant-wide claims resolve to every internal user.
            if ($LoginName -like 'c:0(.s|true*') { return @{ Route = 'Tenant-wide claim'; Via = 'Everyone (includes external users)' } }
            if ($LoginName -like '*spo-grid-all-users*') { return @{ Route = 'Tenant-wide claim'; Via = 'Everyone except external users' } }
            if ($LoginName -like 'c:0!.s|windows*') { return @{ Route = 'Tenant-wide claim'; Via = 'All Users' } }

            # A permission granted straight to this person.
            if ($Member.PrincipalType -eq 1) {
                $MemberUpn = if ($LoginName) { ($LoginName -split '\|')[-1] } else { $null }
                if ($MemberUpn -and ($MemberUpn -ieq $User.userPrincipalName -or $MemberUpn -ieq $User.mail)) {
                    return @{ Route = 'Direct grant'; Via = 'Granted to this user' }
                }
                return $null
            }

            # A directory group holding the permission: the claim carries the group's object id.
            if ($LoginName -match '(?i)(?:federateddirectoryclaimprovider|tenant)\|([0-9a-fA-F-]{36})(_o)?') {
                $GroupId = $Matches[1]
                $OwnersOnly = [bool]$Matches[2]
                if ($GroupIds.Contains($GroupId)) {
                    $GroupLabel = $GroupNameById[$GroupId] ?? $Member.Title ?? $GroupId
                    $Suffix = if ($OwnersOnly) { ' (owners)' } else { '' }
                    return @{ Route = 'Directory group'; Via = "Member of $GroupLabel$Suffix" }
                }
                return $null
            }

            return $null
        }

        $Assignments = @(New-GraphGetRequest -uri "$AssignmentUri`?`$expand=Member,RoleDefinitionBindings" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true)

        foreach ($Assignment in $Assignments) {
            $Member = $Assignment.Member
            if (-not $Member) { continue }

            $Match = Get-PrincipalMatch -Member $Member -User $User -GroupIds $GroupIds -GroupNameById $GroupNameById

            # SharePoint groups hold their own membership, so they need expanding to check.
            if (-not $Match -and $Member.PrincipalType -eq 8) {
                try {
                    $GroupUsers = @(New-GraphGetRequest -uri "$($SPScope.BaseUri)/web/sitegroups($($Member.Id))/users?`$select=Id,Title,LoginName,PrincipalType" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true)
                    foreach ($GroupUser in $GroupUsers) {
                        $Inner = Get-PrincipalMatch -Member $GroupUser -User $User -GroupIds $GroupIds -GroupNameById $GroupNameById
                        if ($Inner) {
                            # Report the SharePoint group as the route, noting how they are in it.
                            $Detail = if ($Inner.Route -eq 'Direct grant') { 'directly a member' } else { $Inner.Via.ToLower() }
                            $Match = @{ Route = 'SharePoint group'; Via = "Member of $($Member.Title) ($Detail)" }
                            break
                        }
                    }
                } catch {
                    Write-Information "Could not expand SharePoint group $($Member.Title): $($_.Exception.Message)"
                }
            }

            if (-not $Match) { continue }

            foreach ($Binding in @($Assignment.RoleDefinitionBindings)) {
                $Paths.Add([PSCustomObject]@{
                        Route            = $Match.Route
                        Via              = $Match.Via
                        PermissionLevel  = $Binding.Name
                        AppliesTo        = if ($Inherits) { 'Whole site (this library inherits)' } elseif ($SPScope.IsLibrary) { 'This library only' } else { 'Whole site' }
                        IsSystemManaged  = ($Binding.RoleTypeKind -eq 1)
                        GrantsRealAccess = ($Binding.RoleTypeKind -ne 1)
                    })
            }
        }

        # --- Site collection administrators bypass all of the above ---
        try {
            $Admins = @(New-GraphGetRequest -uri "$($SPScope.BaseUri)/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,LoginName,PrincipalType" -tenantid $TenantFilter -scope $SPScope.Scope -extraHeaders $SPScope.Headers -UseCertificate -AsApp $true)
            foreach ($Admin in $Admins) {
                $Match = Get-PrincipalMatch -Member $Admin -User $User -GroupIds $GroupIds -GroupNameById $GroupNameById
                if ($Match) {
                    $Paths.Add([PSCustomObject]@{
                            Route            = 'Site collection admin'
                            Via              = if ($Match.Route -eq 'Direct grant') { 'Named as a site collection administrator' } else { $Match.Via }
                            PermissionLevel  = 'Full Control'
                            AppliesTo        = 'Whole site collection'
                            IsSystemManaged  = $false
                            GrantsRealAccess = $true
                        })
                }
            }
        } catch {
            Write-Information "Could not read site collection admins: $($_.Exception.Message)"
        }

        # --- Sharing links this user received, from the cache ---
        $SharingLinksChecked = $false
        try {
            $CachedLinks = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SharePointSharingLinks')
            $SharingLinksChecked = $CachedLinks.Count -gt 0
            $SiteHost = ([System.Uri]$SiteUrl).AbsoluteUri.TrimEnd('/')
            foreach ($Link in $CachedLinks) {
                if (-not $Link.siteUrl -or ($Link.siteUrl.TrimEnd('/') -ne $SiteHost)) { continue }
                $Recipients = @($Link.sharedWith)
                $IsRecipient = $Recipients | Where-Object {
                    $_ -and ($_ -ieq $User.userPrincipalName -or $_ -ieq $User.mail)
                }
                if (-not $IsRecipient) { continue }
                $Paths.Add([PSCustomObject]@{
                        Route            = 'Sharing link'
                        Via              = "Shared '$($Link.fileName)' with them$(if ($Link.driveName) { " in $($Link.driveName)" })"
                        PermissionLevel  = (@($Link.roles) -join ', ')
                        AppliesTo        = 'One item'
                        IsSystemManaged  = $false
                        GrantsRealAccess = $true
                    })
            }
        } catch {
            Write-Information "Could not check sharing links: $($_.Exception.Message)"
        }

        $RealPaths = @($Paths | Where-Object { $_.GrantsRealAccess })
        $Results = [PSCustomObject]@{
            UserPrincipalName   = $User.userPrincipalName
            DisplayName         = $User.displayName
            IsGuest             = $IsGuest
            TargetType          = if ($SPScope.IsLibrary) { 'Library' } else { 'Site' }
            TargetLabel         = $SPScope.TargetLabel
            LibraryInherits     = $Inherits
            HasAccess           = $RealPaths.Count -gt 0
            AccessPathCount     = $RealPaths.Count
            SharingLinksChecked = $SharingLinksChecked
            Paths               = @($Paths)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to check access: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
