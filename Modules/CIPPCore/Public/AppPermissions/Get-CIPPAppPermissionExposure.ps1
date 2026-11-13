function Get-CIPPAppPermissionExposure {
    <#
    .SYNOPSIS
        Lists the apps (service principals) in a tenant holding permissions from the risky permissions catalog.
    .DESCRIPTION
        Returns one row per service principal that holds at least one catalogued application permission or
        delegated grant. Every match carries its suspicion (how unusual it is for an app to hold it) and impact
        (damage if the app is compromised) rating and its categories. Apps owned by a tenant in
        Config/VendorTenantList.json are marked 'Microsoft' (vendorType Microsoft), 'MSP vendor' or 'Known vendor'
        with the vendor's details. Apps owned by the partner tenant CIPP runs from are marked 'Partner tenant'.

        Risk is the per-app rating: the highest permission suspicion, adjusted for who owns the app and how it
        looks in this tenant, crossed with the highest impact. RiskReasons lists every factor that went into it.
        No threshold is applied: callers filter.

        Reads the CIPP reporting database (ServicePrincipals, AppRoleAssignments, OAuth2PermissionGrants), or
        Graph with -Live. Throws ItemNotFoundException when a required cache has not been collected for the tenant.

        Each row also carries the app's last sign-in of any kind (delegated or app-only, as client or resource)
        from the ServicePrincipalSignInActivities cache (the Entra sign-in activity report, Entra ID P1). It is
        read from the cache with -Live too: the report endpoint is too slow to call while a page waits.
        SignInActivityTimestamp says when it was collected; without it SignInActivity is 'Unknown'.

        Credentials count toward Risk wherever they sit: on the service principal (any app) and on the app
        registration (apps registered in this tenant, from the Apps cache). Only unexpired sign-in credentials count:
        secrets and Verify certificates, not token signing or encryption keys.
        A sign-in credential added after the object was created raises suspicion by how recently: 7, 30 or 90
        days. The AppCredentialChanges cache (or, with -Live, the directory audit log, read for every object with
        a credential) dates additions of the last 30 days and says who made them; one added by another app, not
        the app itself, CIPP or a Microsoft service, raises it further. A credential whose start date is more than
        2 days before that addition raises it two steps: the caller sets the start date, so it was backdated past
        the recency windows, or is a certificate reused or uploaded long after it was issued. Beyond the audit
        log's 30 days only the start date is known, and that can be backdated. A credential that replaces another
        (one on the same object expires, or was removed, within 30 days of it) raises suspicion one step only:
        an attacker adds a credential next to the app's own, since removing that breaks the app.

        Federated credentials on the app registration (the AppFederatedCredentials cache, or Graph with -Live) let
        tokens from another identity provider sign in as the app with no secret. They are listed in
        CredentialDetails (Type 'Federated') with the issuer, subject and who runs the issuer. One trusting an issuer
        CIPP does not recognise raises suspicion two steps; one trusting another Entra tenant that is not the
        partner tenant or a listed vendor, one step. GitHub Actions, Azure Kubernetes Service, this tenant and
        common CI providers raise nothing. Graph does not date federated credentials, so their age is not rated.

        Managed identities (servicePrincipalType ManagedIdentity) are their own ownership class whatever their owner
        organisation: no suspicion adjustment, no credential scoring (Azure manages those), and the Azure resource
        named from alternativeNames. Who controls that resource is set in Azure, which CIPP cannot read.

        Microsoft first-party apps and CIPP's own app are rated Low whatever they hold, unless their service principal
        here holds an unexpired sign-in credential: neither Microsoft nor CIPP adds one, so the app is rated Critical
        and is listed even without catalogued permissions. A directory role assigned to one recently or by an app
        raises it like any other app.

        An app owned by another organisation (not this tenant or the partner tenant) consented here, or granted a
        catalogued application permission, in the last 7 or 30 days raises suspicion two or one steps. Apps owned
        here or by the partner tenant are raised one step only when added in the last 30 days with high impact.

        Directory roles held by a service principal, directly or as a member of a role-assignable group, count like
        permissions (Type 'DirectoryRole'), rated from the
        catalog by role template id; other roles fall back on whether Microsoft marks them privileged. A role scoped
        to an administrative unit or a single object is one impact step lower. Roles come from the RoleAssignments
        and RoleDefinitions caches (or Graph with -Live); without them the report covers API permissions only.
        The ServicePrincipalRoleChanges cache (or, with -Live, the directory audit log) says when and by whom a role
        was assigned: in the last 7 days raises suspicion two steps, and by an app other than CIPP or a Microsoft
        service another two, also when the app assigned the role to itself.

        The DelegatedGrantChanges cache (or, with -Live, the directory audit log, read only when an app holds a
        single user's delegated grant) says when and by whom each delegated grant of the last 30 days was added. A
        single user's grant is normally that user's consent: one added by an app other than CIPP or a Microsoft
        service, the client itself included, raises suspicion two steps, also for Microsoft and CIPP apps.

        Exchange RBAC for Applications roles ('Application Mail.Read' and the like) give an app mailbox access in
        Exchange that Entra does not show. They count like permissions (Type 'ExchangeRole'), rated from the catalog
        by role name, from the ExoAppRoleAssignments cache (or Exchange with -Live); without it the report covers
        what Entra shows. A role limited to a management scope or administrative unit is one impact step lower, and
        RiskReasons says when an Entra permission already gives the same access to every mailbox, so the scope
        restricts nothing. One assigned in the last 7 days raises suspicion two steps, also for Microsoft and CIPP
        apps. Exchange does not record who assigned it in the directory audit log.

        Exchange application access policies (the ExoApplicationAccessPolicies cache, or Exchange with -Live) limit
        the mailbox permissions an app holds in Entra, not its Exchange application roles. An app with a valid
        RestrictAccess policy reaches only its groups' members, so those permissions are one impact step lower
        (AccessPolicy 'RestrictAccess'); a DenyAccess policy alone still leaves every other mailbox and lowers nothing.
        A policy Exchange marks invalid is not counted. Without the policies, those permissions count as reaching
        every mailbox.

        Further signals for apps that are not Microsoft's or CIPP's:
        - Credential use, from the AppCredentialSignInActivities cache (Entra ID P1, read from the cache with -Live
          too): each credential's last sign-in is in CredentialDetails, and a recently added credential that has
          already signed in raises suspicion one more step.
        - Microsoft disabling the app (disabledByMicrosoftStatus) or an administrator confirming it compromised in
          Identity Protection (RiskyServicePrincipals cache, or Graph with -Live; Workload Identities Premium) makes
          suspicion Critical; a high or medium Identity Protection risk raises it two or one steps.
        - An app owned elsewhere without a verified publisher, named like a Microsoft product, one step.
        - On the app registration of an app registered here: a redirect URI on plain http, a raw IP address or a
          tunnelling service one step; owners (listed in Owners, every one can add a credential) that are guests
          or apps one step each. Multi-tenant registration and the app instance property lock are noted only.
    .PARAMETER TenantFilter
        The tenant to report on.
    .PARAMETER Live
        Read Graph instead of the reporting database. Application permissions are read per resource API
        (appRoleAssignedTo), which is not subject to the 20-item limit of an expanded relationship.
    .PARAMETER ExcludeDelegated
        Skip delegated grants; the OAuth2PermissionGrants cache is then not required.
    .PARAMETER SkipSignInActivity
        Don't read sign-in activity; every row reports 'Unknown'.
    .PARAMETER ServicePrincipalId
        Return only the row of this service principal (none when it holds no catalogued permission).
    .PARAMETER IncludeUncatalogued
        With -ServicePrincipalId, return the row even when the app holds no catalogued permission: the NHI
        compromise check rates every app it investigates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [switch]$Live,
        [switch]$ExcludeDelegated,
        [switch]$SkipSignInActivity,
        [string]$ServicePrincipalId,
        [switch]$IncludeUncatalogued
    )

    $Types = [System.Collections.Generic.List[string]]::new()
    $Types.Add('ServicePrincipals')
    $Types.Add('AppRoleAssignments')
    if (-not $ExcludeDelegated) { $Types.Add('OAuth2PermissionGrants') }

    $RiskRank = @{ Low = 1; Medium = 2; High = 3; Critical = 4 }
    $RankName = @{ 0 = $null; 1 = 'Low'; 2 = 'Medium'; 3 = 'High'; 4 = 'Critical' }
    $CategoryOrder = @('PrivilegeEscalation', 'DataAccess', 'Integrity', 'Availability')
    # Risk by [suspicion][impact], both ranked 1 (Low) to 4 (Critical).
    $RiskMatrix = @(
        @(0, 0, 0, 0, 0),
        @(0, 1, 1, 2, 3),
        @(0, 1, 2, 3, 3),
        @(0, 1, 2, 3, 4),
        @(0, 2, 3, 4, 4)
    )
    $Rows = [System.Collections.Generic.List[object]]::new()

    $TenantId = $null
    foreach ($Tenant in @(Get-Tenants -TenantFilter $TenantFilter)) {
        $TenantId = [string]$Tenant.customerId
        break
    }

    $Catalog = Get-CIPPRiskyPermissionCatalog
    $ApiByAppId = $Catalog.ApiByAppId
    $ApiByDisplayName = $Catalog.ApiByDisplayName
    $SpFields = @('id', 'appId', 'displayName', 'appOwnerOrganizationId', 'accountEnabled', 'publisherName', 'verifiedPublisher', 'servicePrincipalType', 'signInAudience', 'createdDateTime', 'passwordCredentials', 'keyCredentials', 'alternativeNames', 'disabledByMicrosoftStatus')
    $CacheTimestamp = $null

    if ($Live) {
        $ServicePrincipals = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=$($SpFields -join ',')&`$top=999" -tenantid $TenantFilter)
        $Assignments = [System.Collections.Generic.List[object]]::new()
        foreach ($Sp in $ServicePrincipals) {
            if (-not $ApiByAppId.ContainsKey([string]$Sp.appId)) { continue }
            foreach ($Assignment in @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($Sp.id)/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter)) {
                if ($Assignment.principalType -eq 'ServicePrincipal') { $Assignments.Add($Assignment) }
            }
        }
        $Grants = if ($ExcludeDelegated) { @() } else { @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/oauth2PermissionGrants?$top=999' -tenantid $TenantFilter) }
    } else {
        $RawRows = @{}
        foreach ($Type in $Types) {
            $Data = [System.Collections.Generic.List[object]]::new()
            $Count = $null
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type)) {
                if ($Item.RowKey -eq "$Type-Count") { $Count = $Item } else { $Data.Add($Item) }
            }
            if (-not $Count -and $Data.Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new("No $Type data is cached for $TenantFilter yet. Run a cache sync first.")
            }
            $RawRows[$Type] = $Data.ToArray()
            # A table Timestamp is a DateTimeOffset; rows carry plain UTC DateTimes, which CippJson can store.
            $Collected = if ($Count.Timestamp) { ([datetimeoffset]$Count.Timestamp).UtcDateTime } else { $null }
            if ($Collected -and (-not $CacheTimestamp -or $Collected -lt $CacheTimestamp)) { $CacheTimestamp = $Collected }
        }

        $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Rows $RawRows['ServicePrincipals'] -Fields $SpFields)
        $Assignments = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'AppRoleAssignments' -Rows $RawRows['AppRoleAssignments'] -Fields 'principalId', 'resourceId', 'resourceDisplayName', 'appRoleId', 'createdDateTime', 'servicePrincipalDisplayName', 'servicePrincipalAppId')
        $Grants = if ($ExcludeDelegated) { @() } else { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -Rows $RawRows['OAuth2PermissionGrants'] -Fields 'clientId', 'resourceId', 'consentType', 'scope') }
    }

    # No service principals means the tenant has not synced: nothing can be checked.
    if ($ServicePrincipals.Count -eq 0) {
        throw [System.Management.Automation.ItemNotFoundException]::new("No service principals are available for $TenantFilter yet. Run a cache sync first.")
    }

    $SpById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ResourceApi = @{}
    foreach ($Sp in $ServicePrincipals) {
        if (-not $Sp.id) { continue }
        $SpId = [string]$Sp.id
        $SpById[$SpId] = $Sp
        $Api = $ApiByAppId[[string]$Sp.appId]
        if ($Api) { $ResourceApi[$SpId] = $Api }
    }

    # principalId/clientId -> (permission key -> detail)
    $PermissionsByApp = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $FallbackApps = @{}
    # principalId -> newest catalogued application permission grant (When, Name)
    $NewestGrant = @{}
    $Parsed = [datetimeoffset]::MinValue

    foreach ($Assignment in $Assignments) {
        $Api = $ResourceApi[[string]$Assignment.resourceId]
        if (-not $Api) { $Api = $ApiByDisplayName[[string]$Assignment.resourceDisplayName] }
        if (-not $Api) { continue }
        $Entry = $null
        if (-not $Catalog.Application.TryGetValue("$Api|$($Assignment.appRoleId)", [ref]$Entry)) { continue }
        $PrincipalId = [string]$Assignment.principalId
        if (-not $PrincipalId) { continue }
        $Permissions = $null
        if (-not $PermissionsByApp.TryGetValue($PrincipalId, [ref]$Permissions)) {
            $Permissions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $PermissionsByApp[$PrincipalId] = $Permissions
            $FallbackApps[$PrincipalId] = $Assignment
        }
        $Granted = $null
        if ($Assignment.createdDateTime -is [datetime]) {
            $Granted = $Assignment.createdDateTime.ToUniversalTime()
        } elseif ($Assignment.createdDateTime -and [datetimeoffset]::TryParse([string]$Assignment.createdDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
            $Granted = $Parsed.UtcDateTime
        }
        if ($Granted -and (-not $NewestGrant[$PrincipalId] -or $Granted -gt $NewestGrant[$PrincipalId].When)) {
            $NewestGrant[$PrincipalId] = @{ When = $Granted; Name = [string]$Entry.name }
        }
        $Key = "$Api|Application|$($Entry.name)"
        if (-not $Permissions.ContainsKey($Key)) {
            $Permissions[$Key] = [PSCustomObject]@{
                Api         = $Entry.api
                Name        = $Entry.name
                Type        = 'Application'
                Suspicion   = $Entry.suspicion
                Impact      = $Entry.impact
                Categories  = @($Entry.categories)
                Reason      = $Entry.reason
                ConsentType = $null
            }
        }
    }

    foreach ($Grant in $Grants) {
        $Api = $ResourceApi[[string]$Grant.resourceId]
        if (-not $Api -or [string]::IsNullOrWhiteSpace($Grant.scope)) { continue }
        $ClientId = [string]$Grant.clientId
        if (-not $ClientId) { continue }
        $ConsentType = if ($Grant.consentType -eq 'AllPrincipals') { 'AllPrincipals' } else { 'Principal' }
        foreach ($Scope in ([string]$Grant.scope).Split([char[]]' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $Entry = $null
            if (-not $Catalog.Delegated.TryGetValue("$Api|$Scope", [ref]$Entry)) { continue }
            $Permissions = $null
            if (-not $PermissionsByApp.TryGetValue($ClientId, [ref]$Permissions)) {
                $Permissions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $PermissionsByApp[$ClientId] = $Permissions
            }
            $Key = "$Api|Delegated|$($Entry.name)"
            $Existing = $null
            if ($Permissions.TryGetValue($Key, [ref]$Existing)) {
                # Admin consent for everyone outweighs a single user's consent.
                if ($ConsentType -eq 'AllPrincipals') { $Existing.ConsentType = 'AllPrincipals' }
                continue
            }
            $Permissions[$Key] = [PSCustomObject]@{
                Api           = $Entry.api
                Name          = $Entry.name
                Type          = 'Delegated'
                Suspicion     = $Entry.suspicion
                Impact        = $Entry.impact
                Categories    = @($Entry.categories)
                Reason        = $Entry.reason
                ConsentType   = $ConsentType
                AddedDateTime = $null
                AddedBy       = $null
                AddedByType   = $null
            }
        }
    }

    # Directory roles held by service principals, directly or through a role-assignable group, read best effort:
    # without them the report covers API permissions.
    $RoleAssignments = @()
    $RoleDefinitions = @()
    # group id -> its service principal members, and the group's name
    $GroupAppMembers = @{}
    $GroupNames = @{}
    if ($Live) {
        try {
            $RoleAssignments = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId&$top=999' -tenantid $TenantFilter)
            $RoleDefinitions = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/roleManagement/directory/roleDefinitions?$select=id,templateId,displayName,isBuiltIn,isPrivileged' -tenantid $TenantFilter)
            $AssigneeIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($RoleAssignment in $RoleAssignments) { [void]$AssigneeIds.Add([string]$RoleAssignment.principalId) }
            $Requests = [System.Collections.Generic.List[object]]::new()
            foreach ($Group in @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/groups?$filter=isAssignableToRole eq true&$select=id,displayName&$top=999' -tenantid $TenantFilter)) {
                if (-not $AssigneeIds.Contains([string]$Group.id)) { continue }
                $GroupNames[[string]$Group.id] = [string]$Group.displayName
                $Requests.Add(@{ id = [string]$Group.id; method = 'GET'; url = "groups/$($Group.id)/members/microsoft.graph.servicePrincipal?`$select=id&`$top=999" })
            }
            if ($Requests.Count -gt 0) {
                foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $Requests.ToArray())) {
                    if ([int]$Response.status -eq 200) { $GroupAppMembers[[string]$Response.id] = @($Response.body.value) }
                }
            }
        } catch {
            Write-Information "Directory roles unavailable for $($TenantFilter): $($_.Exception.Message)"
        }
    } else {
        foreach ($Type in 'RoleAssignments', 'RoleDefinitions') {
            $TypeRows = [System.Collections.Generic.List[object]]::new()
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type)) {
                if ($Item.RowKey -ne "$Type-Count") { $TypeRows.Add($Item) }
            }
            if ($TypeRows.Count -eq 0) { continue }
            if ($Type -eq 'RoleAssignments') {
                $RoleAssignments = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type -Rows $TypeRows.ToArray() -Fields 'principalId', 'roleDefinitionId', 'directoryScopeId', 'principal', 'servicePrincipalMembers')
                foreach ($RoleAssignment in $RoleAssignments) {
                    if ($null -eq $RoleAssignment.servicePrincipalMembers) { continue }
                    $GroupAppMembers[[string]$RoleAssignment.principalId] = @($RoleAssignment.servicePrincipalMembers)
                    $GroupNames[[string]$RoleAssignment.principalId] = [string]$RoleAssignment.principal.displayName
                }
            } else {
                $RoleDefinitions = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type -Rows $TypeRows.ToArray() -Fields 'id', 'templateId', 'displayName', 'isBuiltIn', 'isPrivileged')
            }
        }
    }
    $RoleDefById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Definition in $RoleDefinitions) {
        if ($Definition.id) { $RoleDefById[[string]$Definition.id] = $Definition }
    }
    $RoleHolders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($RoleAssignment in $RoleAssignments) {
        $AssigneeId = [string]$RoleAssignment.principalId
        $DefinitionId = [string]$RoleAssignment.roleDefinitionId
        if (-not $AssigneeId -or -not $DefinitionId) { continue }
        $ViaGroupId = $null
        $HolderIds = if ($SpById.ContainsKey($AssigneeId)) {
            @($AssigneeId)
        } elseif ($GroupAppMembers.ContainsKey($AssigneeId)) {
            $ViaGroupId = $AssigneeId
            @(foreach ($Member in $GroupAppMembers[$AssigneeId]) { [string]$Member.id })
        } else {
            continue
        }
        $Definition = $null
        [void]$RoleDefById.TryGetValue($DefinitionId, [ref]$Definition)
        # Built-in roles' definition id is their template id; a custom role's template id is its own id.
        $RoleId = if ($Definition.templateId) { [string]$Definition.templateId } else { $DefinitionId }
        $Entry = $null
        if (-not $Catalog.DirectoryRole.TryGetValue($RoleId, [ref]$Entry)) {
            $RoleName = if ($Definition.displayName) { [string]$Definition.displayName } else { "Unknown role $DefinitionId" }
            $Entry = if (-not $Definition) {
                [PSCustomObject]@{ name = $RoleName; suspicion = 'Medium'; impact = 'Medium'; categories = @('PrivilegeEscalation'); reason = 'Role definition not available: what it allows is unknown.' }
            } elseif ($Definition.isBuiltIn -eq $false) {
                [PSCustomObject]@{ name = $RoleName; suspicion = 'Medium'; impact = 'High'; categories = @('PrivilegeEscalation'); reason = 'Custom role: what it allows depends on the permissions it was given, which can include adding credentials to apps.' }
            } elseif ($Definition.isPrivileged -eq $true) {
                [PSCustomObject]@{ name = $RoleName; suspicion = 'Medium'; impact = 'High'; categories = @('PrivilegeEscalation'); reason = 'Microsoft marks this role privileged: it can be used to gain more access.' }
            } else {
                [PSCustomObject]@{ name = $RoleName; suspicion = 'Low'; impact = 'Low'; categories = @(); reason = 'Built-in role Microsoft does not mark privileged.' }
            }
        }
        $ScopeId = [string]$RoleAssignment.directoryScopeId
        $Scope = if (-not $ScopeId -or $ScopeId -eq '/') {
            'Tenant'
        } elseif ($ScopeId.StartsWith('/administrativeUnits/', [System.StringComparison]::OrdinalIgnoreCase)) {
            'Administrative unit'
        } else {
            'Single object'
        }
        $Impact = [string]$Entry.impact
        $Reason = [string]$Entry.reason
        if ($Scope -ne 'Tenant') {
            $Impact = $RankName[[Math]::Max(1, [int]$RiskRank[$Impact] - 1)]
            $Reason = "$Reason Scoped to $(if ($Scope -eq 'Administrative unit') { 'an administrative unit' } else { 'a single object' }) ($ScopeId): impact one step lower."
        }
        $ViaGroupName = $null
        if ($ViaGroupId) {
            $ViaGroupName = if ($GroupNames[$ViaGroupId]) { $GroupNames[$ViaGroupId] } else { $ViaGroupId }
            $Reason = "$Reason Held through membership of the role-assignable group $ViaGroupName."
        }
        foreach ($PrincipalId in $HolderIds) {
            if (-not $PrincipalId -or -not $SpById.ContainsKey($PrincipalId)) { continue }
            $Permissions = $null
            if (-not $PermissionsByApp.TryGetValue($PrincipalId, [ref]$Permissions)) {
                $Permissions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $PermissionsByApp[$PrincipalId] = $Permissions
            }
            [void]$RoleHolders.Add($PrincipalId)
            $Permissions["Microsoft Entra ID|DirectoryRole|$RoleId|$ScopeId|$ViaGroupId"] = [PSCustomObject]@{
                Api              = 'Microsoft Entra ID'
                Name             = [string]$Entry.name
                Type             = 'DirectoryRole'
                Suspicion        = [string]$Entry.suspicion
                Impact           = $Impact
                Categories       = @($Entry.categories)
                Reason           = $Reason
                ConsentType      = $null
                RoleId           = $RoleId
                Scope            = $Scope
                DirectoryScopeId = if ($ScopeId) { $ScopeId } else { '/' }
                ViaGroupId       = $ViaGroupId
                ViaGroupName     = $ViaGroupName
                AddedDateTime    = $null
                AddedBy          = $null
                AddedByType      = $null
            }
        }
    }

    # Exchange RBAC for Applications: mailbox access Exchange gives an app itself, not visible in Entra. Read best
    # effort: without it the report covers what Entra shows.
    $ExoAppAssignments = @()
    if ($Live) {
        try {
            $ExoAppAssignments = @(Get-CIPPExoAppRoleAssignment -TenantFilter $TenantFilter)
        } catch {
            Write-Information "Exchange application roles unavailable for $($TenantFilter): $($_.Exception.Message)"
        }
    } else {
        $TypeRows = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoAppRoleAssignments')) {
            if ($Item.RowKey -ne 'ExoAppRoleAssignments-Count') { $TypeRows.Add($Item) }
        }
        if ($TypeRows.Count -gt 0) {
            $ExoAppAssignments = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoAppRoleAssignments' -Rows $TypeRows.ToArray() -Fields 'role', 'servicePrincipalId', 'delegating', 'enabled', 'customResourceScope', 'customResourceScopeFilter', 'recipientAdministrativeUnitScope', 'whenCreatedUTC')
        }
    }
    foreach ($ExoAssignment in $ExoAppAssignments) {
        $PrincipalId = [string]$ExoAssignment.servicePrincipalId
        # A delegating assignment lets its holder assign the role, it gives no mailbox access itself.
        if ($ExoAssignment.enabled -eq $false -or $ExoAssignment.delegating -eq $true -or -not $PrincipalId -or -not $SpById.ContainsKey($PrincipalId)) { continue }
        $RoleName = [string]$ExoAssignment.role
        $Entry = $null
        if (-not $Catalog.ExchangeRole.TryGetValue($RoleName, [ref]$Entry)) {
            # Microsoft adds application roles over time: one not catalogued yet still reaches mailbox data.
            $Entry = [PSCustomObject]@{ name = $RoleName; suspicion = 'Medium'; impact = 'High'; categories = @('DataAccess'); coveredBy = @(); reason = 'Exchange application role not in the catalog: it gives the app access to mailbox data.' }
        }
        $Impact = [string]$Entry.impact
        $Reason = [string]$Entry.reason
        $Scope = 'Organization'
        $ScopeName = $null
        if ($ExoAssignment.customResourceScope) {
            $Scope = 'Management scope'
            $ScopeName = [string]$ExoAssignment.customResourceScope
            $Reason = "$Reason Scoped to the management scope $ScopeName$(if ($ExoAssignment.customResourceScopeFilter) { " ($($ExoAssignment.customResourceScopeFilter))" }): impact one step lower."
        } elseif ($ExoAssignment.recipientAdministrativeUnitScope) {
            $Scope = 'Administrative unit'
            $ScopeName = [string]$ExoAssignment.recipientAdministrativeUnitScope
            $Reason = "$Reason Scoped to the administrative unit $($ScopeName): impact one step lower."
        }
        if ($Scope -ne 'Organization') { $Impact = $RankName[[Math]::Max(1, [int]$RiskRank[$Impact] - 1)] }
        $Created = $null
        if ($ExoAssignment.whenCreatedUTC -is [datetime]) {
            $Created = $ExoAssignment.whenCreatedUTC.ToUniversalTime()
        } elseif ($ExoAssignment.whenCreatedUTC -and [datetimeoffset]::TryParse([string]$ExoAssignment.whenCreatedUTC, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
            $Created = $Parsed.UtcDateTime
        }
        $Permissions = $null
        if (-not $PermissionsByApp.TryGetValue($PrincipalId, [ref]$Permissions)) {
            $Permissions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $PermissionsByApp[$PrincipalId] = $Permissions
        }
        $Permissions["Exchange Online|ExchangeRole|$RoleName|$Scope|$ScopeName"] = [PSCustomObject]@{
            Api           = 'Exchange Online'
            Name          = $RoleName
            Type          = 'ExchangeRole'
            Suspicion     = [string]$Entry.suspicion
            Impact        = $Impact
            Categories    = @($Entry.categories)
            Reason        = $Reason
            ConsentType   = $null
            Scope         = $Scope
            ScopeName     = $ScopeName
            ScopeFilter   = if ($Scope -eq 'Management scope') { [string]$ExoAssignment.customResourceScopeFilter } else { $null }
            CoveredBy     = @($Entry.coveredBy)
            AddedDateTime = $Created
            AddedBy       = $null
            AddedByType   = $null
        }
    }

    # Application access policies limit which mailboxes the mailbox permissions an app holds in Entra reach, not its
    # Exchange application roles. Read best effort: without them those permissions count as reaching every mailbox.
    $AccessPolicies = @()
    $AccessPoliciesKnown = $false
    if ($Live) {
        try {
            $AccessPolicies = @(Get-CIPPExoApplicationAccessPolicy -TenantFilter $TenantFilter)
            $AccessPoliciesKnown = $true
        } catch {
            Write-Information "Exchange application access policies unavailable for $($TenantFilter): $($_.Exception.Message)"
        }
    } else {
        $TypeRows = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoApplicationAccessPolicies')) {
            if ($Item.RowKey -eq 'ExoApplicationAccessPolicies-Count') { $AccessPoliciesKnown = $true } else { $TypeRows.Add($Item) }
        }
        if ($TypeRows.Count -gt 0) {
            $AccessPoliciesKnown = $true
            $AccessPolicies = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ExoApplicationAccessPolicies' -Rows $TypeRows.ToArray() -Fields 'appId', 'accessRight', 'scopeName', 'scopeIdentity', 'isValid')
        }
    }
    if ($AccessPolicies.Count -gt 0) {
        # The application permissions the policies apply to: Exchange data through Graph, Outlook REST and EWS.
        $PolicyScopedPermissions = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
                'Microsoft Graph|Mail.Read', 'Microsoft Graph|Mail.ReadBasic', 'Microsoft Graph|Mail.ReadBasic.All', 'Microsoft Graph|Mail.ReadWrite', 'Microsoft Graph|Mail.Send'
                'Microsoft Graph|MailboxSettings.Read', 'Microsoft Graph|MailboxSettings.ReadWrite', 'Microsoft Graph|Calendars.Read', 'Microsoft Graph|Calendars.ReadWrite'
                'Microsoft Graph|Contacts.Read', 'Microsoft Graph|Contacts.ReadWrite'
                'Exchange Online|full_access_as_app', 'Exchange Online|Mail.Read', 'Exchange Online|Mail.ReadWrite', 'Exchange Online|Mail.Send', 'Exchange Online|Calendars.Read'
                'Exchange Online|Calendars.ReadWrite', 'Exchange Online|Calendars.ReadWrite.All', 'Exchange Online|Contacts.Read', 'Exchange Online|Contacts.ReadWrite'
                'Exchange Online|MailboxSettings.Read', 'Exchange Online|MailboxSettings.ReadWrite'
            ), [System.StringComparer]::OrdinalIgnoreCase)
        $PoliciesByAppId = @{}
        foreach ($Policy in $AccessPolicies) {
            $PolicyAppId = ([string]$Policy.appId).ToLowerInvariant()
            if (-not $PolicyAppId) { continue }
            if (-not $PoliciesByAppId.ContainsKey($PolicyAppId)) { $PoliciesByAppId[$PolicyAppId] = [System.Collections.Generic.List[object]]::new() }
            $PoliciesByAppId[$PolicyAppId].Add($Policy)
        }
        foreach ($Pair in $PermissionsByApp.GetEnumerator()) {
            $Sp = $SpById[$Pair.Key]
            if (-not $Sp.appId) { continue }
            # A policy for '*' applies to every app.
            $AppPolicies = @(@($PoliciesByAppId[([string]$Sp.appId).ToLowerInvariant()]) + @($PoliciesByAppId['*']) | Where-Object { $_ })
            if ($AppPolicies.Count -eq 0) { continue }
            $Valid = @($AppPolicies | Where-Object { $_.isValid -ne $false })
            $Invalid = @($AppPolicies | Where-Object { $_.isValid -eq $false })
            $GroupName = { param($Policy) if ($Policy.scopeName) { [string]$Policy.scopeName } else { [string]$Policy.scopeIdentity } }
            # Exchange denies a DenyAccess group's members first, then allows only the members of any RestrictAccess
            # group: one RestrictAccess policy limits the app to its groups, whatever else applies.
            $Restrict = @($Valid | Where-Object accessRight -EQ 'RestrictAccess' | ForEach-Object { & $GroupName $_ } | Sort-Object -Unique)
            $Deny = @($Valid | Where-Object accessRight -EQ 'DenyAccess' | ForEach-Object { & $GroupName $_ } | Sort-Object -Unique)
            $InvalidNote = if ($Invalid.Count -gt 0) { " Exchange marks the application access policy for $((@($Invalid | ForEach-Object { & $GroupName $_ } | Sort-Object -Unique)) -join ', ') invalid (its group may be gone): not counted." } else { '' }
            foreach ($D in $Pair.Value.Values) {
                if ($D.Type -ne 'Application' -or -not $PolicyScopedPermissions.Contains("$($D.Api)|$($D.Name)")) { continue }
                if ($Restrict.Count -gt 0) {
                    $D | Add-Member -NotePropertyName AccessPolicy -NotePropertyValue 'RestrictAccess' -Force
                    $D | Add-Member -NotePropertyName AccessPolicyScope -NotePropertyValue ($Restrict -join ', ') -Force
                    $D.Impact = $RankName[[Math]::Max(1, [int]$RiskRank[[string]$D.Impact] - 1)]
                    $D.Reason = "$($D.Reason) Limited by an application access policy to the members of $($Restrict -join ', ')$(if ($Deny.Count -gt 0) { " except those of $($Deny -join ', ')" }): impact one step lower.$InvalidNote"
                } elseif ($Deny.Count -gt 0) {
                    $D | Add-Member -NotePropertyName AccessPolicy -NotePropertyValue 'DenyAccess' -Force
                    $D | Add-Member -NotePropertyName AccessPolicyScope -NotePropertyValue ($Deny -join ', ') -Force
                    $D.Reason = "$($D.Reason) An application access policy keeps it from the members of $($Deny -join ', '), but it still reaches every other mailbox.$InvalidNote"
                } else {
                    $D.Reason = "$($D.Reason)$InvalidNote"
                }
            }
        }
    }

    $CippAppId =[System.Environment]::GetEnvironmentVariable('ApplicationID')
    $PartnerTenantId = [System.Environment]::GetEnvironmentVariable('TenantID')
    $VendorTenants = Get-CIPPVendorTenantMap

    # Microsoft's and CIPP's apps act with access that is not visible as grants: one with credentials of its own gets a row too.
    foreach ($Sp in $SpById.Values) {
        if ((-not $Sp.passwordCredentials -and -not $Sp.keyCredentials) -or $PermissionsByApp.ContainsKey([string]$Sp.id)) { continue }
        $OwnerVendor = $null
        if ($Sp.appOwnerOrganizationId) { [void]$VendorTenants.TryGetValue([string]$Sp.appOwnerOrganizationId, [ref]$OwnerVendor) }
        if (($CippAppId -and $Sp.appId -eq $CippAppId) -or ($OwnerVendor.VendorType -eq 'Microsoft' -and $Sp.servicePrincipalType -ne 'ManagedIdentity')) {
            $PermissionsByApp[[string]$Sp.id] = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
    }

    if ($ServicePrincipalId) {
        $Only = $null
        [void]$PermissionsByApp.TryGetValue($ServicePrincipalId, [ref]$Only)
        $PermissionsByApp = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Only) {
            $PermissionsByApp[$ServicePrincipalId] = $Only
        } elseif ($IncludeUncatalogued -and $SpById.ContainsKey($ServicePrincipalId)) {
            $PermissionsByApp[$ServicePrincipalId] = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
    }

    # appId -> sign-in activity; stays $null when the cache was never collected.
    $ActivityFields = @('lastSignInActivity', 'delegatedClientSignInActivity', 'applicationAuthenticationClientSignInActivity', 'delegatedResourceSignInActivity', 'applicationAuthenticationResourceSignInActivity')
    $ActivityByAppId = $null
    $ActivityTimestamp = $null
    if (-not $SkipSignInActivity -and $PermissionsByApp.Count -gt 0) {
        $ActivityRows = [System.Collections.Generic.List[object]]::new()
        $ActivityCount = $null
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities')) {
            if ($Item.RowKey -eq 'ServicePrincipalSignInActivities-Count') { $ActivityCount = $Item } else { $ActivityRows.Add($Item) }
        }
        if ($ActivityCount -or $ActivityRows.Count -gt 0) {
            $ActivityTimestamp = if ($ActivityCount.Timestamp) { ([datetimeoffset]$ActivityCount.Timestamp).UtcDateTime } else { $null }
            $ActivityByAppId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if ($ActivityRows.Count -gt 0) {
                foreach ($Item in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities' -Rows $ActivityRows.ToArray() -Fields (@('appId') + $ActivityFields))) {
                    if ($Item.appId) { $ActivityByAppId[[string]$Item.appId] = $Item }
                }
            }
        }
    }
    # keyId -> when that credential last signed in, from the AppCredentialSignInActivities cache (Entra ID P1); read from
    # the cache with -Live too, like the app's own sign-in activity. $null when never collected.
    $CredentialUseByKeyId = $null
    if (-not $SkipSignInActivity -and $PermissionsByApp.Count -gt 0) {
        $UseRows = [System.Collections.Generic.List[object]]::new()
        $UseCount = $null
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppCredentialSignInActivities')) {
            if ($Item.RowKey -eq 'AppCredentialSignInActivities-Count') { $UseCount = $Item } else { $UseRows.Add($Item) }
        }
        if ($UseCount -or $UseRows.Count -gt 0) {
            $CredentialUseByKeyId = @{}
            if ($UseRows.Count -gt 0) {
                foreach ($Item in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'AppCredentialSignInActivities' -Rows $UseRows.ToArray() -Fields 'keyId', 'signInActivity')) {
                    $Raw = $Item.signInActivity.lastSignInDateTime
                    $When = $null
                    if ($Raw -is [datetime]) {
                        $When = $Raw.ToUniversalTime()
                    } elseif ($Raw -and [datetimeoffset]::TryParse([string]$Raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
                        $When = $Parsed.UtcDateTime
                    }
                    if ($Item.keyId -and $When) { $CredentialUseByKeyId[([string]$Item.keyId).ToLowerInvariant()] = $When }
                }
            }
        }
    }

    # Identity Protection's risk on each service principal (Workload Identities Premium), read best effort.
    $RiskBySpId = @{}
    if ($PermissionsByApp.Count -gt 0) {
        $RiskRows = @()
        if ($Live) {
            try {
                $RiskRows = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/identityProtection/riskyServicePrincipals?$select=id,riskLevel,riskState,riskDetail,riskLastUpdatedDateTime&$top=500' -tenantid $TenantFilter)
            } catch {
                Write-Information "Risky service principals unavailable for $($TenantFilter): $($_.Exception.Message)"
            }
        } else {
            $TypeRows = [System.Collections.Generic.List[object]]::new()
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'RiskyServicePrincipals')) {
                if ($Item.RowKey -ne 'RiskyServicePrincipals-Count') { $TypeRows.Add($Item) }
            }
            if ($TypeRows.Count -gt 0) {
                $RiskRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'RiskyServicePrincipals' -Rows $TypeRows.ToArray() -Fields 'id', 'riskLevel', 'riskState', 'riskDetail', 'riskLastUpdatedDateTime')
            }
        }
        foreach ($Row in $RiskRows) {
            if ($Row.id -and $Row.riskState -in 'atRisk', 'confirmedCompromised') { $RiskBySpId[[string]$Row.id] = $Row }
        }
    }
    $Now = [datetime]::UtcNow

    # App registrations of the result's apps registered in this tenant: their credentials live there.
    $GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    $AppRegByAppId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $OwnAppIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($PrincipalId in $PermissionsByApp.Keys) {
        $Sp = $null
        [void]$SpById.TryGetValue($PrincipalId, [ref]$Sp)
        if ($Sp.appId -and $TenantId -and [string]$Sp.appOwnerOrganizationId -eq $TenantId) { [void]$OwnAppIds.Add([string]$Sp.appId) }
    }
    $AppFields = @('id', 'appId', 'createdDateTime', 'passwordCredentials', 'keyCredentials', 'signInAudience', 'web', 'spa', 'publicClient', 'servicePrincipalLockConfiguration', 'disabledByMicrosoftStatus', 'owners')
    if ($OwnAppIds.Count -gt 0) {
        if ($Live) {
            $Requests = [System.Collections.Generic.List[object]]::new()
            foreach ($OwnAppId in $OwnAppIds) {
                # owners is a relationship: expanded, not selected
                if ($OwnAppId -match $GuidPattern) { $Requests.Add(@{ id = $OwnAppId; method = 'GET'; url = "applications(appId='$OwnAppId')?`$select=$(($AppFields -ne 'owners') -join ',')&`$expand=owners(`$select=id,displayName,userPrincipalName,userType,appId)" }) }
            }
            if ($Requests.Count -gt 0) {
                try {
                    foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $Requests.ToArray())) {
                        if ([int]$Response.status -eq 200 -and $Response.body.appId) { $AppRegByAppId[[string]$Response.body.appId] = $Response.body }
                    }
                } catch {
                    Write-Information "App registrations unavailable for $($TenantFilter): $($_.Exception.Message)"
                }
            }
        } else {
            $AppRows = [System.Collections.Generic.List[object]]::new()
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Apps')) {
                if ($Item.RowKey -ne 'Apps-Count') { $AppRows.Add($Item) }
            }
            if ($AppRows.Count -gt 0) {
                foreach ($App in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Apps' -Rows $AppRows.ToArray() -Fields $AppFields)) {
                    if ($App.appId -and $OwnAppIds.Contains([string]$App.appId)) { $AppRegByAppId[[string]$App.appId] = $App }
                }
            }
        }
    }

    # Federated credentials of those app registrations, by appId: tokens from another identity provider that sign in
    # as the app without a secret. $null when they were not read.
    $FederatedByAppId = $null
    if ($AppRegByAppId.Count -gt 0) {
        $FederatedRows = $null
        if ($Live) {
            try {
                $FederatedRows = @(Get-CIPPAppFederatedCredential -TenantFilter $TenantFilter -Applications @($AppRegByAppId.Values))
            } catch {
                Write-Information "Federated credentials unavailable for $($TenantFilter): $($_.Exception.Message)"
            }
        } else {
            $Cached = [System.Collections.Generic.List[object]]::new()
            $CachedCount = $null
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppFederatedCredentials')) {
                if ($Item.RowKey -eq 'AppFederatedCredentials-Count') { $CachedCount = $Item } else { $Cached.Add($Item) }
            }
            if ($CachedCount -or $Cached.Count -gt 0) {
                $FederatedRows = if ($Cached.Count -gt 0) { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'AppFederatedCredentials' -Rows $Cached.ToArray() -Fields 'appId', 'credentialId', 'name', 'issuer', 'subject', 'audiences', 'description', 'claimsMatchingExpression') } else { @() }
            }
        }
        if ($null -ne $FederatedRows) {
            $FederatedByAppId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Row in $FederatedRows) {
                if (-not $Row.appId) { continue }
                $List = $null
                if (-not $FederatedByAppId.TryGetValue([string]$Row.appId, [ref]$List)) {
                    $List = [System.Collections.Generic.List[object]]::new()
                    $FederatedByAppId[[string]$Row.appId] = $List
                }
                $List.Add($Row)
            }
        }
    }

    # Who added the credentials of the last 30 days (the audit log's reach), keyed 'objectId|keyId'. Read for every
    # object holding a credential, whatever its start date: the caller sets that, so it can be backdated past the
    # window. $null when the audit log was not read.
    $AuditStart = $Now.AddDays(-30)
    $CredentialObjectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($PrincipalId in $PermissionsByApp.Keys) {
        $Sp = $null
        [void]$SpById.TryGetValue($PrincipalId, [ref]$Sp)
        $AppReg = $null
        if ($Sp.appId) { [void]$AppRegByAppId.TryGetValue([string]$Sp.appId, [ref]$AppReg) }
        foreach ($Owner in @($Sp, $AppReg)) {
            if ($Owner.id -and $Owner.servicePrincipalType -ne 'ManagedIdentity' -and ($Owner.passwordCredentials -or $Owner.keyCredentials)) { [void]$CredentialObjectIds.Add([string]$Owner.id) }
        }
    }
    $CredentialAudits = $null
    # object id -> when sign-in credentials were removed from it
    $CredentialRemovals = @{}
    if ($CredentialObjectIds.Count -gt 0) {
        $AuditRows = @()
        if ($Live) {
            $AuditFrom = $AuditStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Requests = [System.Collections.Generic.List[object]]::new()
            foreach ($ObjectId in $CredentialObjectIds) {
                if ($ObjectId -match $GuidPattern) {
                    $Requests.Add(@{ id = $ObjectId; method = 'GET'; url = "auditLogs/directoryAudits?`$filter=activityDateTime ge $AuditFrom and targetResources/any(t:t/id eq '$ObjectId')&`$select=activityDateTime,activityDisplayName,initiatedBy,targetResources&`$top=999" })
                }
            }
            if ($Requests.Count -gt 0) {
                try {
                    $Events = [System.Collections.Generic.List[object]]::new()
                    foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $Requests.ToArray() -asapp $true)) {
                        if ([int]$Response.status -ne 200) { continue }
                        foreach ($Event in @($Response.body.value)) { if ($Event) { $Events.Add($Event) } }
                    }
                    $AuditRows = @(ConvertFrom-CIPPCredentialAuditEvent -Events $Events.ToArray())
                    $CredentialAudits = @{}
                } catch {
                    Write-Information "Directory audit log unavailable for $($TenantFilter): $($_.Exception.Message)"
                }
            }
        } else {
            $Cached = [System.Collections.Generic.List[object]]::new()
            $CachedCount = $null
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'AppCredentialChanges')) {
                if ($Item.RowKey -eq 'AppCredentialChanges-Count') { $CachedCount = $Item } else { $Cached.Add($Item) }
            }
            if ($CachedCount -or $Cached.Count -gt 0) {
                $CredentialAudits = @{}
                if ($Cached.Count -gt 0) {
                    $AuditRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'AppCredentialChanges' -Rows $Cached.ToArray() -Fields 'action', 'targetId', 'keyId', 'keyUsage', 'activityDateTime', 'initiatedByType', 'initiatedByName', 'initiatedByAppId', 'initiatedByServicePrincipalId')
                }
            }
        }
        if ($null -ne $CredentialAudits) {
            foreach ($Row in $AuditRows) {
                if ($Row.action -ne 'Removed') {
                    $CredentialAudits["$($Row.targetId)|$($Row.keyId)".ToLowerInvariant()] = $Row
                } elseif ($Row.keyUsage -eq 'Verify') {
                    # Sign-in credentials removed, by object: a credential added around then replaced one.
                    $Removed = $null
                    if ($Row.activityDateTime -is [datetime]) {
                        $Removed = $Row.activityDateTime.ToUniversalTime()
                    } elseif ($Row.activityDateTime -and [datetimeoffset]::TryParse([string]$Row.activityDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
                        $Removed = $Parsed.UtcDateTime
                    }
                    if (-not $Removed) { continue }
                    $Key = ([string]$Row.targetId).ToLowerInvariant()
                    if (-not $CredentialRemovals[$Key]) { $CredentialRemovals[$Key] = [System.Collections.Generic.List[datetime]]::new() }
                    $CredentialRemovals[$Key].Add($Removed)
                }
            }
        }
    }

    # Who assigned the directory roles in the last 30 days, keyed 'servicePrincipalId|roleId' to every assignment
    # event; $null when the audit log was not read.
    $RoleAudits = $null
    $AuditedHolders = [System.Collections.Generic.List[string]]::new()
    foreach ($PrincipalId in $PermissionsByApp.Keys) {
        if ($RoleHolders.Contains($PrincipalId)) { $AuditedHolders.Add($PrincipalId) }
    }
    if ($AuditedHolders.Count -gt 0) {
        $RoleAuditRows = @()
        if ($Live) {
            $AuditFrom = $AuditStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Requests = [System.Collections.Generic.List[object]]::new()
            foreach ($ObjectId in $AuditedHolders) {
                if ($ObjectId -match $GuidPattern) {
                    $Requests.Add(@{ id = $ObjectId; method = 'GET'; url = "auditLogs/directoryAudits?`$filter=activityDateTime ge $AuditFrom and targetResources/any(t:t/id eq '$ObjectId')&`$select=id,activityDateTime,activityDisplayName,initiatedBy,targetResources&`$top=999" })
                }
            }
            if ($Requests.Count -gt 0) {
                try {
                    $Events = [System.Collections.Generic.List[object]]::new()
                    foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests $Requests.ToArray() -asapp $true)) {
                        if ([int]$Response.status -ne 200) { continue }
                        foreach ($Event in @($Response.body.value)) { if ($Event) { $Events.Add($Event) } }
                    }
                    $RoleAuditRows = @(ConvertFrom-CIPPRoleAuditEvent -Events $Events.ToArray())
                    $RoleAudits = @{}
                } catch {
                    Write-Information "Directory audit log unavailable for $($TenantFilter): $($_.Exception.Message)"
                }
            }
        } else {
            $Cached = [System.Collections.Generic.List[object]]::new()
            $CachedCount = $null
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalRoleChanges')) {
                if ($Item.RowKey -eq 'ServicePrincipalRoleChanges-Count') { $CachedCount = $Item } else { $Cached.Add($Item) }
            }
            if ($CachedCount -or $Cached.Count -gt 0) {
                $RoleAudits = @{}
                if ($Cached.Count -gt 0) {
                    $RoleAuditRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipalRoleChanges' -Rows $Cached.ToArray() -Fields 'targetId', 'roleId', 'groupId', 'activityDateTime', 'initiatedByType', 'initiatedByName', 'initiatedByAppId', 'initiatedByServicePrincipalId')
                }
            }
        }
        if ($null -ne $RoleAudits) {
            foreach ($Row in $RoleAuditRows) {
                # A role held through a group dates from when the app joined the group.
                $Key = if ($Row.groupId) { "$($Row.targetId)|group:$($Row.groupId)" } else { "$($Row.targetId)|$($Row.roleId)" }
                $Key = $Key.ToLowerInvariant()
                $List = $RoleAudits[$Key]
                if (-not $List) {
                    $List = [System.Collections.Generic.List[object]]::new()
                    $RoleAudits[$Key] = $List
                }
                $List.Add($Row)
            }
        }
    }

    # Who added the delegated grants of the last 30 days, keyed by client service principal id to every event;
    # $null when the audit log was not read. Read only when a result app holds a single user's grant.
    $GrantAudits = $null
    $HasUserGrant = $false
    foreach ($Permissions in $PermissionsByApp.Values) {
        foreach ($D in $Permissions.Values) {
            if ($D.ConsentType -eq 'Principal') { $HasUserGrant = $true; break }
        }
        if ($HasUserGrant) { break }
    }
    if ($HasUserGrant) {
        $GrantAuditRows = @()
        if ($Live) {
            $AuditFrom = $AuditStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
            try {
                $Events = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Add delegated permission grant' and activityDateTime ge $AuditFrom&`$select=id,activityDateTime,activityDisplayName,initiatedBy,targetResources&`$top=999" -tenantid $TenantFilter -AsApp $true)
                $GrantAuditRows = @(ConvertFrom-CIPPGrantAuditEvent -Events $Events)
                $GrantAudits = @{}
            } catch {
                Write-Information "Directory audit log unavailable for $($TenantFilter): $($_.Exception.Message)"
            }
        } else {
            $Cached = [System.Collections.Generic.List[object]]::new()
            $CachedCount = $null
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'DelegatedGrantChanges')) {
                if ($Item.RowKey -eq 'DelegatedGrantChanges-Count') { $CachedCount = $Item } else { $Cached.Add($Item) }
            }
            if ($CachedCount -or $Cached.Count -gt 0) {
                $GrantAudits = @{}
                if ($Cached.Count -gt 0) {
                    $GrantAuditRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'DelegatedGrantChanges' -Rows $Cached.ToArray() -Fields 'clientId', 'resourceId', 'consentType', 'scope', 'activityDateTime', 'initiatedByType', 'initiatedByName', 'initiatedByAppId', 'initiatedByServicePrincipalId')
                }
            }
        }
        if ($null -ne $GrantAudits) {
            foreach ($Row in $GrantAuditRows) {
                $Key = ([string]$Row.clientId).ToLowerInvariant()
                $List = $GrantAudits[$Key]
                if (-not $List) {
                    $List = [System.Collections.Generic.List[object]]::new()
                    $GrantAudits[$Key] = $List
                }
                $List.Add($Row)
            }
        }
    }

    foreach ($Pair in $PermissionsByApp.GetEnumerator()) {
        $PrincipalId = $Pair.Key
        $Sp = $null
        [void]$SpById.TryGetValue($PrincipalId, [ref]$Sp)
        $Fallback = $FallbackApps[$PrincipalId]
        $AppId = if ($Sp) { [string]$Sp.appId } else { [string]$Fallback.servicePrincipalAppId }
        $DisplayName = if ($Sp.displayName) { [string]$Sp.displayName } elseif ($Fallback.servicePrincipalDisplayName) { [string]$Fallback.servicePrincipalDisplayName } else { $PrincipalId }
        $OwnerTenantId = [string]$Sp.appOwnerOrganizationId
        # A managed identity belongs to an Azure resource in this tenant, whatever its owner organisation says.
        $IsManagedIdentity = [bool]($Sp.servicePrincipalType -eq 'ManagedIdentity')
        $Vendor = $null
        if ($OwnerTenantId -and -not $IsManagedIdentity) { [void]$VendorTenants.TryGetValue($OwnerTenantId, [ref]$Vendor) }
        $IsMicrosoftApp = [bool]($Vendor -and $Vendor.VendorType -eq 'Microsoft')
        $IsPartnerApp = [bool]($PartnerTenantId -and $OwnerTenantId -eq $PartnerTenantId -and -not $IsManagedIdentity)
        $AzureResourceId = if ($IsManagedIdentity) { @($Sp.alternativeNames) -like '/subscriptions/*' | Select-Object -First 1 } else { $null }
        $Ownership = if ($IsManagedIdentity) {
            'Managed identity'
        } elseif (-not $OwnerTenantId) {
            'Unknown'
        } elseif ($IsMicrosoftApp) {
            'Microsoft'
        } elseif ($TenantId -and $OwnerTenantId -eq $TenantId) {
            'This tenant'
        } elseif ($IsPartnerApp) {
            'Partner tenant'
        } elseif ($Vendor.VendorType -eq 'Consumer') {
            'Personal account'
        } elseif ($Vendor) {
            if ($Vendor.VendorType -eq 'MSP') { 'MSP vendor' } else { 'Known vendor' }
        } else {
            'Third party'
        }
        # Credentials on the service principal and, for apps registered here, on the app registration.
        $AppReg = $null
        if ($AppId) { [void]$AppRegByAppId.TryGetValue($AppId, [ref]$AppReg) }
        $CredentialDetails = [System.Collections.Generic.List[object]]::new()
        $CredentialCount = 0
        $AppRegCredentialCount = 0
        $NewestTier = 0
        $NewestWindow = $null
        $NewestReplaces = $null
        $NewestCredential = $null
        $NewestUsed = $false
        $AddedByApp = $null
        $Backdated = $null
        # Azure manages a managed identity's credentials and Graph cannot add one: there is nothing to rate.
        foreach ($Location in $(if ($IsManagedIdentity) { @() } else { 'enterprise app', 'app registration' })) {
            $Owner = if ($Location -eq 'enterprise app') { $Sp } else { $AppReg }
            if (-not $Owner) { continue }
            # A signing certificate is stored as a Sign key, a Verify key and a key password, all with its thumbprint.
            $SigningKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Key in $Owner.keyCredentials) {
                if ($Key.usage -eq 'Sign' -and $Key.customKeyIdentifier) { [void]$SigningKeys.Add([string]$Key.customKeyIdentifier) }
            }
            # Every sign-in credential, expired ones included, and the unexpired ones added after setup.
            $SignInKeys = [System.Collections.Generic.List[object]]::new()
            $Candidates = [System.Collections.Generic.List[object]]::new()
            $OwnerCreated = $null
            $Parsed = [datetimeoffset]::MinValue
            if ($Owner.createdDateTime -is [datetime]) {
                $OwnerCreated = $Owner.createdDateTime.ToUniversalTime()
            } elseif ($Owner.createdDateTime -and [datetimeoffset]::TryParse([string]$Owner.createdDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
                $OwnerCreated = $Parsed.UtcDateTime
            }
            foreach ($Kind in 'Secret', 'Certificate') {
                $List = if ($Kind -eq 'Secret') { $Owner.passwordCredentials } else { $Owner.keyCredentials }
                foreach ($Credential in $List) {
                    if (-not $Credential) { continue }
                    # Only secrets and Verify certificates sign the app in; Sign and Encrypt keys protect tokens.
                    $Purpose = if ($Credential.usage -eq 'Encrypt') {
                        'Token encryption'
                    } elseif ($Credential.usage -eq 'Sign' -or ($Credential.customKeyIdentifier -and $SigningKeys.Contains([string]$Credential.customKeyIdentifier))) {
                        'Token signing'
                    } else {
                        'Sign-in'
                    }
                    $Audit = if ($null -ne $CredentialAudits) { $CredentialAudits["$($Owner.id)|$($Credential.keyId)".ToLowerInvariant()] } else { $null }
                    # Start, end, and when the audit log recorded the credential being added.
                    $RawTimes = @($Credential.startDateTime, $Credential.endDateTime, $Audit.activityDateTime)
                    $Times = [object[]]::new(3)
                    for ($t = 0; $t -lt 3; $t++) {
                        if ($RawTimes[$t] -is [datetime]) {
                            $Times[$t] = $RawTimes[$t].ToUniversalTime()
                        } elseif ($RawTimes[$t] -and [datetimeoffset]::TryParse([string]$RawTimes[$t], [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
                            $Times[$t] = $Parsed.UtcDateTime
                        }
                    }
                    $Added = if ($Times[2]) { $Times[2] } else { $Times[0] }
                    $Expired = [bool]($Times[1] -and $Times[1] -lt $Now)
                    $LastUsed = if ($null -ne $CredentialUseByKeyId -and $Credential.keyId) { $CredentialUseByKeyId[([string]$Credential.keyId).ToLowerInvariant()] } else { $null }
                    # Flags: what this credential contributed to the rating (AddedRecently, Rotation, AddedByApp, Backdated).
                    $Detail = [PSCustomObject]@{
                        Location           = if ($Location -eq 'enterprise app') { 'Enterprise app' } else { 'App registration' }
                        Type               = $Kind
                        Purpose            = $Purpose
                        Expired            = $Expired
                        DisplayName        = [string]$Credential.displayName
                        KeyId              = [string]$Credential.keyId
                        StartDateTime      = $Times[0]
                        AddedDateTime      = $Added
                        AddedBy            = $Audit.initiatedByName
                        AddedByType        = $Audit.initiatedByType
                        EndDateTime        = $Times[1]
                        LastSignInDateTime = $LastUsed
                        Flags              = [System.Collections.Generic.List[string]]::new()
                    }
                    $CredentialDetails.Add($Detail)
                    if ($Purpose -eq 'Sign-in') { $SignInKeys.Add(@{ KeyId = [string]$Credential.keyId; Added = $Added; End = $Times[1] }) }
                    # An expired credential can no longer sign in, and token keys never could.
                    if ($Purpose -ne 'Sign-in' -or $Expired) { continue }
                    if ($Location -eq 'enterprise app') { $CredentialCount++ } else { $AppRegCredentialCount++ }
                    # The portal and addPassword start a credential when it is added; the audit log says when that
                    # was. A start more than 2 days earlier was set by hand to look older, or is a certificate
                    # reused or uploaded long after it was issued: one certificate per app keeps this quiet.
                    if ($Times[2] -and $Times[0] -and ($Times[2] - $Times[0]).TotalDays -gt 2) {
                        $Detail.Flags.Add('Backdated')
                        if (-not $Backdated) {
                            $Backdated = if ($Kind -eq 'Secret') {
                                'Secret on its {0} backdated: added {1:yyyy-MM-dd} but marked valid from {2:yyyy-MM-dd}' -f $Location, $Times[2], $Times[0]
                            } else {
                                'Certificate on its {0} added {1:yyyy-MM-dd} but valid from {2:yyyy-MM-dd}: backdated, or reused or uploaded long after it was issued' -f $Location, $Times[2], $Times[0]
                            }
                        }
                    }
                    # Credentials created together with the app or service principal are part of setting it up.
                    if (-not $Added -or $Added -gt $Now -or ($OwnerCreated -and ($Added - $OwnerCreated).TotalDays -lt 1)) { continue }
                    $Candidates.Add(@{ KeyId = [string]$Credential.keyId; Added = $Added; Kind = $Kind; Used = $LastUsed -and $LastUsed -ge $Added; Detail = $Detail })
                    if ($Audit.initiatedByType -eq 'Application') {
                        $ActorSp = $null
                        if ($Audit.initiatedByServicePrincipalId) { [void]$SpById.TryGetValue([string]$Audit.initiatedByServicePrincipalId, [ref]$ActorSp) }
                        $ActorVendor = $null
                        if ($ActorSp.appOwnerOrganizationId) { [void]$VendorTenants.TryGetValue([string]$ActorSp.appOwnerOrganizationId, [ref]$ActorVendor) }
                        $IsSelf = $Audit.initiatedByAppId -eq $AppId -or $Audit.initiatedByServicePrincipalId -eq $PrincipalId
                        $IsTrustedActor = ($CippAppId -and $CippAppId -in @($Audit.initiatedByAppId, $ActorSp.appId)) -or $ActorVendor.VendorType -eq 'Microsoft'
                        if (-not $IsSelf -and -not $IsTrustedActor) {
                            $Detail.Flags.Add('AddedByApp')
                            if (-not $AddedByApp) { $AddedByApp = "$Kind added to its $Location by the app $($Audit.initiatedByName)" }
                        }
                    }
                }
            }
            # A rotation replaces a credential: one that expires, or was removed, within 30 days of the new one. An
            # attacker adds one next to the app's own, because removing that breaks the app and gets noticed.
            $Removals = $CredentialRemovals[([string]$Owner.id).ToLowerInvariant()]
            foreach ($Candidate in $Candidates) {
                $Replaces = $null
                foreach ($Other in $SignInKeys) {
                    if ($Other.KeyId -eq $Candidate.KeyId -or -not $Other.End -or ($Other.Added -and $Other.Added -ge $Candidate.Added)) { continue }
                    if ([Math]::Abs(($Other.End - $Candidate.Added).TotalDays) -le 30) { $Replaces = 'a credential that expires within 30 days of it'; break }
                }
                if (-not $Replaces) {
                    foreach ($Removed in $Removals) {
                        if ([Math]::Abs(($Removed - $Candidate.Added).TotalDays) -le 30) { $Replaces = 'a credential removed within 30 days of it'; break }
                    }
                }
                $Age = ($Now - $Candidate.Added).TotalDays
                $AgeTier = if ($Age -le 7) { 3 } elseif ($Age -le 30) { 2 } elseif ($Age -le 90) { 1 } else { 0 }
                $Tier = if ($Replaces) { [Math]::Min(1, $AgeTier) } else { $AgeTier }
                if ($AgeTier -ge 2) { $Candidate.Detail.Flags.Add('AddedRecently') }
                if ($Replaces) { $Candidate.Detail.Flags.Add('Rotation') }
                if ($Tier -gt $NewestTier) {
                    $NewestTier = $Tier
                    $NewestWindow = @{ 3 = '7'; 2 = '30'; 1 = '90' }[$AgeTier]
                    $NewestReplaces = $Replaces
                    $NewestCredential = "$($Candidate.Kind) added to its $Location"
                    $NewestUsed = [bool]$Candidate.Used
                }
            }
        }

        # Federated credentials on its app registration: a token from the issuer for the subject signs in as the app,
        # with no secret or certificate to find or expire. Rated by who runs the issuer.
        $FederatedCount = 0
        $FederatedReasons = [System.Collections.Generic.List[object]]::new()
        $FederatedList = $null
        if ($AppReg -and $null -ne $FederatedByAppId -and $AppId) { [void]$FederatedByAppId.TryGetValue($AppId, [ref]$FederatedList) }
        foreach ($Federated in @($FederatedList)) {
            if (-not $Federated) { continue }
            $FederatedCount++
            $Issuer = ([string]$Federated.issuer).TrimEnd('/')
            $IssuerTenant = if ($Issuer -match '^https://(login\.microsoftonline\.com|sts\.windows\.net)/([0-9a-fA-F-]{36})(/v2\.0)?$') { $Matches[2] } else { $null }
            $IssuerVendor = $null
            if ($IssuerTenant) { [void]$VendorTenants.TryGetValue($IssuerTenant, [ref]$IssuerVendor) }
            # Steps: how much a credential trusting this issuer raises suspicion.
            $Trust, $Steps = if ($Issuer -eq 'https://token.actions.githubusercontent.com' -or $Issuer -like 'https://token.actions.githubusercontent.com/*') {
                'GitHub Actions', 0
            } elseif ($Issuer -match '^https://[a-z0-9-]+\.oic\.prod-aks\.azure\.com/') {
                'Azure Kubernetes Service', 0
            } elseif ($IssuerTenant -and $TenantId -and $IssuerTenant -eq $TenantId) {
                'This tenant (a managed identity or app here)', 0
            } elseif ($IssuerTenant -and $PartnerTenantId -and $IssuerTenant -eq $PartnerTenantId) {
                'Your partner tenant', 0
            } elseif ($IssuerTenant -and $IssuerVendor) {
                "Entra tenant of $($IssuerVendor.Name)", 0
            } elseif ($IssuerTenant) {
                "Another Entra tenant ($IssuerTenant)", 1
            } elseif ($Issuer -in 'https://gitlab.com', 'https://app.terraform.io', 'https://accounts.google.com', 'https://cognito-identity.amazonaws.com') {
                ([uri]$Issuer).Host, 0
            } else {
                'Unrecognised issuer', 2
            }
            $Matching = if ($Federated.claimsMatchingExpression) { "subjects matching $($Federated.claimsMatchingExpression)" } else { [string]$Federated.subject }
            $CredentialDetails.Add([PSCustomObject]@{
                    Location      = 'App registration'
                    Type          = 'Federated'
                    Purpose       = 'Sign-in'
                    Expired       = $false
                    DisplayName   = [string]$Federated.name
                    KeyId         = [string]$Federated.credentialId
                    Issuer        = [string]$Federated.issuer
                    Subject       = $Matching
                    Trust         = $Trust
                    StartDateTime = $null
                    AddedDateTime = $null
                    AddedBy       = $null
                    AddedByType   = $null
                    EndDateTime   = $null
                    LastSignInDateTime = $null
                    Flags         = @(if ($Steps -gt 0) { 'UntrustedIssuer' })
                })
            if ($Steps -gt 0) {
                $FederatedReasons.Add(@{
                        Steps = $Steps
                        Text  = if ($Steps -ge 2) {
                            "Federated credential '$($Federated.name)' on its app registration trusts tokens from $($Federated.issuer), not a recognised identity provider: whoever runs that issuer signs in as this app with no secret (a self-hosted cluster looks the same; suspicion two steps higher)"
                        } else {
                            "Federated credential '$($Federated.name)' on its app registration lets identities in another Entra tenant ($IssuerTenant) sign in as this app (suspicion one step higher)"
                        }
                    })
            }
        }

        # Index 0: any flow, 1: delegated as client, 2: app-only as client, 3/4: as a resource.
        $SignIns = [object[]]::new($ActivityFields.Count)
        $LastSignIn = $null
        $DaysSinceSignIn = $null
        $SignInActivity = 'Unknown'
        if ($null -ne $ActivityByAppId) {
            $Activity = $null
            [void]$ActivityByAppId.TryGetValue([string]$AppId, [ref]$Activity)
            for ($f = 0; $f -lt $ActivityFields.Count; $f++) {
                $Raw = if ($Activity) { $Activity.($ActivityFields[$f]).lastSignInDateTime } else { $null }
                if ($Raw -is [datetime]) {
                    $SignIns[$f] = $Raw.ToUniversalTime()
                } elseif ($Raw) {
                    $Parsed = [datetimeoffset]::MinValue
                    if ([datetimeoffset]::TryParse([string]$Raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) { $SignIns[$f] = $Parsed.UtcDateTime }
                }
                if ($SignIns[$f] -and (-not $LastSignIn -or $SignIns[$f] -gt $LastSignIn)) { $LastSignIn = $SignIns[$f] }
            }
            $SignInActivity = if (-not $LastSignIn) {
                'No sign-in recorded'
            } else {
                $DaysSinceSignIn = [int][Math]::Max(0, [Math]::Floor(($Now - $LastSignIn).TotalDays))
                if ($DaysSinceSignIn -le 30) { 'Active' } elseif ($DaysSinceSignIn -le 90) { 'Idle 30+ days' } else { 'Stale 90+ days' }
            }
        }

        $Details = [object[]]$Pair.Value.Values
        $DetailKeys = [string[]]::new($Details.Count)
        $MaxSuspicion = 0
        $MaxImpact = 0
        $ApplicationCount = 0
        $RoleCount = 0
        $ExchangeRoleCount = 0
        $RecentExchangeRole = $null
        $RecentRole = $null
        $RoleAddedByApp = $null
        $Parsed = [datetimeoffset]::MinValue
        $HasAllPrincipals = $false
        $CategorySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        for ($i = 0; $i -lt $Details.Count; $i++) {
            $D = $Details[$i]
            $Suspicion = [int]$RiskRank[[string]$D.Suspicion]
            $Impact = [int]$RiskRank[[string]$D.Impact]
            $DetailKeys[$i] = '{0}|{1}|{2}|{3}|{4}' -f (5 - $Impact), (5 - $Suspicion), $D.Api, $D.Type, $D.Name
            if ($Suspicion -gt $MaxSuspicion) { $MaxSuspicion = $Suspicion }
            if ($Impact -gt $MaxImpact) { $MaxImpact = $Impact }
            if ($D.Type -eq 'Application') { $ApplicationCount++ }
            if ($D.ConsentType -eq 'AllPrincipals') { $HasAllPrincipals = $true }
            foreach ($Category in $D.Categories) { [void]$CategorySet.Add([string]$Category) }
            if ($D.Type -eq 'ExchangeRole') {
                $ExchangeRoleCount++
                if (-not $RecentExchangeRole -and $D.AddedDateTime -and ($Now - $D.AddedDateTime).TotalDays -le 7) { $RecentExchangeRole = $D.Name }
                continue
            }
            if ($D.Type -ne 'DirectoryRole') { continue }
            $RoleCount++
            $RoleLabel = if ($D.ViaGroupId) { "$($D.Name) (through group $($D.ViaGroupName))" } else { $D.Name }
            $AuditKey = if ($D.ViaGroupId) { "$PrincipalId|group:$($D.ViaGroupId)" } else { "$PrincipalId|$($D.RoleId)" }
            $RoleEvents = if ($null -ne $RoleAudits) { $RoleAudits[$AuditKey.ToLowerInvariant()] } else { $null }
            foreach ($RoleEvent in $RoleEvents) {
                $When = $null
                if ($RoleEvent.activityDateTime -is [datetime]) {
                    $When = $RoleEvent.activityDateTime.ToUniversalTime()
                } elseif ($RoleEvent.activityDateTime -and [datetimeoffset]::TryParse([string]$RoleEvent.activityDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
                    $When = $Parsed.UtcDateTime
                }
                if ($When -and (-not $D.AddedDateTime -or $When -gt $D.AddedDateTime)) {
                    $D.AddedDateTime = $When
                    $D.AddedBy = $RoleEvent.initiatedByName
                    $D.AddedByType = $RoleEvent.initiatedByType
                }
                if (-not $RecentRole -and $When -and ($Now - $When).TotalDays -le 7) { $RecentRole = $RoleLabel }
                if (-not $RoleAddedByApp -and $RoleEvent.initiatedByType -eq 'Application') {
                    $ActorSp = $null
                    if ($RoleEvent.initiatedByServicePrincipalId) { [void]$SpById.TryGetValue([string]$RoleEvent.initiatedByServicePrincipalId, [ref]$ActorSp) }
                    $ActorVendor = $null
                    if ($ActorSp.appOwnerOrganizationId) { [void]$VendorTenants.TryGetValue([string]$ActorSp.appOwnerOrganizationId, [ref]$ActorVendor) }
                    # An app assigning a role to itself is escalation, not housekeeping: only CIPP and Microsoft are trusted.
                    if (-not (($CippAppId -and $CippAppId -in @($RoleEvent.initiatedByAppId, $ActorSp.appId)) -or $ActorVendor.VendorType -eq 'Microsoft')) {
                        $IsSelf = $RoleEvent.initiatedByAppId -eq $AppId -or $RoleEvent.initiatedByServicePrincipalId -eq $PrincipalId
                        $RoleAddedByApp = if ($IsSelf) { "$RoleLabel assigned by the app to itself" } else { "$RoleLabel assigned by the app $($RoleEvent.initiatedByName)" }
                    }
                }
            }
        }
        # A single user's delegated grant is normally that user's own consent. One added by an app, the client
        # itself included, gives the app that user's access without the user seeing a consent prompt.
        $GrantAddedByApp = $null
        $GrantEvents = if ($null -ne $GrantAudits) { $GrantAudits[$PrincipalId.ToLowerInvariant()] } else { $null }
        foreach ($GrantEvent in $GrantEvents) {
            $Api = $ResourceApi[[string]$GrantEvent.resourceId]
            if (-not $Api) { continue }
            $Scopes = [System.Collections.Generic.HashSet[string]]::new([string[]]([string]$GrantEvent.scope).Split([char[]]' ', [System.StringSplitOptions]::RemoveEmptyEntries), [System.StringComparer]::OrdinalIgnoreCase)
            $Matched = @(foreach ($D in $Details) { if ($D.Type -eq 'Delegated' -and $D.Api -eq $Api -and $Scopes.Contains([string]$D.Name)) { $D } })
            if ($Matched.Count -eq 0) { continue }
            $When = $null
            if ($GrantEvent.activityDateTime -is [datetime]) {
                $When = $GrantEvent.activityDateTime.ToUniversalTime()
            } elseif ($GrantEvent.activityDateTime -and [datetimeoffset]::TryParse([string]$GrantEvent.activityDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
                $When = $Parsed.UtcDateTime
            }
            foreach ($D in $Matched) {
                if ($When -and (-not $D.AddedDateTime -or $When -gt $D.AddedDateTime)) {
                    $D.AddedDateTime = $When
                    $D.AddedBy = $GrantEvent.initiatedByName
                    $D.AddedByType = $GrantEvent.initiatedByType
                }
            }
            if ($GrantAddedByApp -or $GrantEvent.initiatedByType -ne 'Application') { continue }
            $SingleUser = $GrantEvent.consentType -eq 'Principal' -or (-not $GrantEvent.consentType -and @($Matched | Where-Object ConsentType -EQ 'Principal').Count -gt 0)
            if (-not $SingleUser) { continue }
            $ActorSp = $null
            if ($GrantEvent.initiatedByServicePrincipalId) { [void]$SpById.TryGetValue([string]$GrantEvent.initiatedByServicePrincipalId, [ref]$ActorSp) }
            $ActorVendor = $null
            if ($ActorSp.appOwnerOrganizationId) { [void]$VendorTenants.TryGetValue([string]$ActorSp.appOwnerOrganizationId, [ref]$ActorVendor) }
            if (($CippAppId -and $CippAppId -in @($GrantEvent.initiatedByAppId, $ActorSp.appId)) -or $ActorVendor.VendorType -eq 'Microsoft') { continue }
            $IsSelf = $GrantEvent.initiatedByAppId -eq $AppId -or $GrantEvent.initiatedByServicePrincipalId -eq $PrincipalId
            $GrantAddedByApp = 'Delegated {0} for a single user granted by {1}' -f (@($Matched.Name) -join ', '), $(if ($IsSelf) { 'the app to itself' } else { "the app $($GrantEvent.initiatedByName)" })
        }
        # Explicit type arguments: without them PowerShell sorts a copy of the items array.
        [Array]::Sort[string, object]($DetailKeys, $Details, [System.StringComparer]::OrdinalIgnoreCase)
        $IsCippApp = [bool]($CippAppId -and $AppId -eq $CippAppId)
        # A Microsoft or CIPP app listed only to check its credentials, and holding none that sign in.
        if ($Details.Count -eq 0 -and $CredentialCount -eq 0 -and -not $IncludeUncatalogued) { continue }

        $Labels = [string[]]::new($Details.Count)
        for ($i = 0; $i -lt $Details.Count; $i++) {
            $D = $Details[$i]
            $Labels[$i] = if ($D.Type -eq 'DirectoryRole') {
                '{0}: {1} (directory role{2}{3}, suspicion {4}, impact {5})' -f $D.Api, $D.Name, $(if ($D.Scope -ne 'Tenant') { ", scoped to $($D.DirectoryScopeId)" }), $(if ($D.ViaGroupId) { ", through group $($D.ViaGroupName)" }), $D.Suspicion, $D.Impact
            } elseif ($D.Type -eq 'ExchangeRole') {
                '{0}: {1} (Exchange application role{2}, suspicion {3}, impact {4})' -f $D.Api, $D.Name, $(if ($D.Scope -ne 'Organization') { ", scoped to $($D.Scope.ToLowerInvariant()) $($D.ScopeName)" }), $D.Suspicion, $D.Impact
            } elseif ($D.ConsentType) {
                '{0}: {1} ({2}, suspicion {3}, impact {4}, {5})' -f $D.Api, $D.Name, $D.Type, $D.Suspicion, $D.Impact, $D.ConsentType
            } else {
                '{0}: {1} ({2}, suspicion {3}, impact {4})' -f $D.Api, $D.Name, $D.Type, $D.Suspicion, $D.Impact
            }
        }
        $Categories = [System.Collections.Generic.List[string]]::new()
        foreach ($Category in $CategoryOrder) { if ($CategorySet.Contains($Category)) { $Categories.Add($Category) } }

        # Context-aware rating: the permissions' suspicion moved by who owns the app and how it looks here, crossed with impact.
        $Reasons = [System.Collections.Generic.List[string]]::new()
        $Reasons.Add($(if ($Details.Count -eq 0) {
                    'No catalogued permissions or directory roles'
                } else {
                    '{0}: highest impact {1}, highest suspicion {2}' -f $(if ($RoleCount -gt 0 -and $ExchangeRoleCount -gt 0) { 'Permissions, directory roles and Exchange application roles' } elseif ($RoleCount -gt 0) { 'Permissions and directory roles' } elseif ($ExchangeRoleCount -gt 0) { 'Permissions and Exchange application roles' } else { 'Permissions' }), $RankName[$MaxImpact], $RankName[$MaxSuspicion]
                }))
        $AppSuspicion = $MaxSuspicion
        $EffectiveImpact = $MaxImpact
        if ($ApplicationCount -eq 0 -and $RoleCount -eq 0 -and $ExchangeRoleCount -eq 0 -and -not $HasAllPrincipals -and $EffectiveImpact -gt 1) {
            $EffectiveImpact--
            $Reasons.Add('Only delegated permissions, each consented by individual users: limited to what those users can reach (impact one step lower)')
        }
        # Entra and Exchange grants add up: a scoped Exchange role restricts nothing when Entra already gives the same
        # access to every mailbox.
        foreach ($D in $Details) {
            if ($D.Type -ne 'ExchangeRole' -or $D.Scope -eq 'Organization') { continue }
            $CoveredBy = @($D.CoveredBy)
            # An Entra permission an application access policy limits to a group does not reach every mailbox.
            $Broader = @(foreach ($Other in $Details) { if ($Other.Type -eq 'Application' -and $Other.AccessPolicy -ne 'RestrictAccess' -and "$($Other.Api)|$($Other.Name)" -in $CoveredBy) { "$($Other.Api) $($Other.Name)" } })
            if ($Broader.Count -eq 0) { continue }
            $Reach = if ($AccessPoliciesKnown) { 'which no application access policy limits to a group' } else { 'which reaches every mailbox unless an application access policy limits it' }
            $Reasons.Add(('{0} is scoped in Exchange to the {1} {2}, but the app also holds {3} in Entra, {4}: the Exchange scope restricts nothing' -f $D.Name, $D.Scope.ToLowerInvariant(), $D.ScopeName, ($Broader -join ', '), $Reach))
        }
        # Access given to the app recently or by another app: raises Microsoft and CIPP apps too.
        $ActorFlags = [System.Collections.Generic.List[string]]::new()
        if ($RecentRole) { $ActorFlags.Add("Directory role $RecentRole assigned in the last 7 days (suspicion two steps higher)") }
        if ($RecentExchangeRole) { $ActorFlags.Add("Exchange application role $RecentExchangeRole assigned in the last 7 days (suspicion two steps higher)") }
        if ($RoleAddedByApp) { $ActorFlags.Add("Directory role $RoleAddedByApp rather than by a person (suspicion two steps higher)") }
        if ($GrantAddedByApp) { $ActorFlags.Add("$GrantAddedByApp rather than by that user's consent (suspicion two steps higher)") }
        # Microsoft stops issuing tokens to an app it finds malicious or abusive, on the app or on this tenant's copy.
        $DisabledBy = @([string]$Sp.disabledByMicrosoftStatus, [string]$AppReg.disabledByMicrosoftStatus) | Where-Object { $_ -and $_ -ne 'NotDisabled' } | Select-Object -First 1
        $Impersonates = $null
        $RiskLevel = 0
        if ($IsCippApp -or $IsMicrosoftApp) {
            $AppSuspicion = 1
            $RiskLevel = 1
            $Reasons.Add($(if ($IsCippApp) { "CIPP's own app: its exposure is the security of your partner tenant" } else { 'Microsoft first-party app' }))
            if ($CredentialCount -gt 0) {
                $AppSuspicion = 4
                $MaxImpact = 4
                $EffectiveImpact = 4
                $RiskLevel = 4
                $Reasons.Add(("{0} sign-in credential(s) on its service principal in this tenant, which {1} never adds: whoever holds one signs in as this app with all of its access, including access not visible as grants (Critical)" -f $CredentialCount, $(if ($IsCippApp) { 'CIPP' } else { 'Microsoft' })))
            } elseif ($FederatedCount -gt 0) {
                # Only CIPP's own registration can sit here, when the report runs on the partner tenant.
                $AppSuspicion = 4
                $MaxImpact = 4
                $EffectiveImpact = 4
                $RiskLevel = 4
                $Reasons.Add("$FederatedCount federated credential(s) on its app registration, which CIPP never adds: whoever controls the trusted issuer signs in as this app with all of its access, with no secret (Critical)")
            } elseif ($ActorFlags.Count -gt 0) {
                foreach ($Flag in $ActorFlags) { $AppSuspicion += 2; $Reasons.Add($Flag) }
                $AppSuspicion = [Math]::Min(4, $AppSuspicion)
                $RiskLevel = $RiskMatrix[$AppSuspicion][[Math]::Max(1, $EffectiveImpact)]
            }
        } else {
            switch ($Ownership) {
                'Partner tenant' {
                    $AppSuspicion--
                    $Reasons.Add('Registered in your partner tenant (suspicion one step lower); a compromise there reaches this access in every client that consented')
                }
                'MSP vendor' { $AppSuspicion--; $Reasons.Add("Known MSP vendor $($Vendor.Name) (suspicion one step lower)") }
                'Known vendor' { $AppSuspicion--; $Reasons.Add("Known vendor $($Vendor.Name) (suspicion one step lower)") }
                'This tenant' { $Reasons.Add('Registered in this tenant: its credentials are managed here') }
                'Managed identity' {
                    # /subscriptions/{sub}/resourceGroups/{rg}/providers/{namespace}/{type}/{name}[/{type}/{name}...]
                    $Segments = ([string]$AzureResourceId).Trim('/').Split('/')
                    $ResourceGroup = $null
                    $ResourceType = $null
                    $ResourceName = $null
                    for ($s = 0; $s -lt $Segments.Count - 1; $s++) {
                        if ($Segments[$s] -eq 'resourceGroups') { $ResourceGroup = $Segments[$s + 1] }
                        if ($Segments[$s] -eq 'providers' -and $s + 3 -lt $Segments.Count) {
                            $ResourceType = "$($Segments[$s + 1])/$($Segments[$s + 2])"
                            $ResourceName = $Segments[$s + 3]
                            break
                        }
                    }
                    $TypeName = switch ($ResourceType) {
                        'Microsoft.Automation/automationAccounts' { 'Automation account' }
                        'Microsoft.Web/sites' { 'App Service or Function App' }
                        'Microsoft.Logic/workflows' { 'Logic App' }
                        'Microsoft.Compute/virtualMachines' { 'virtual machine' }
                        'Microsoft.HybridCompute/machines' { 'Arc-enabled server' }
                        'Microsoft.DataFactory/factories' { 'Data Factory' }
                        default { $ResourceType }
                    }
                    $Where = if ($ResourceGroup) { " (resource group $ResourceGroup)" } else { '' }
                    $Reasons.Add($(if ($ResourceType -eq 'Microsoft.ManagedIdentity/userAssignedIdentities') {
                                "User-assigned managed identity $ResourceName$($Where): every Azure resource it is attached to, and anyone who can attach it, acts with this access. Who can is set in Azure, which CIPP cannot read"
                            } elseif ($ResourceName) {
                                "Managed identity of $TypeName $ResourceName$($Where): anyone who can run code on or change that resource acts with this access. Who can is set in Azure, which CIPP cannot read"
                            } else {
                                'Managed identity of an Azure resource: anyone who can run code on or change that resource acts with this access. Who can is set in Azure, which CIPP cannot read'
                            }))
                }
                'Third party' {
                    if ($Sp.verifiedPublisher.displayName) {
                        $Reasons.Add("Third party not on the vendor list; verified publisher $($Sp.verifiedPublisher.displayName)")
                    } else {
                        $AppSuspicion++
                        $Reasons.Add('Third party not on the vendor list and without a verified publisher (suspicion one step higher)')
                    }
                }
                'Unknown' { $AppSuspicion++; $Reasons.Add('The tenant that owns the app is unknown (suspicion one step higher)') }
                'Personal account' {
                    $AppSuspicion += 2
                    $Reasons.Add('Registered with a personal Microsoft account rather than by an organisation: no verifiable owner (suspicion two steps higher)')
                }
            }
            if ($CredentialCount -gt 0 -and $Ownership -ne 'This tenant') {
                $AppSuspicion += 2
                $Reasons.Add("$CredentialCount sign-in credential(s) on its service principal in this tenant, a known persistence technique for apps owned elsewhere (suspicion two steps higher)")
            }
            if ($NewestTier -gt 0) {
                $AppSuspicion += $NewestTier
                $Steps = @{ 3 = 'three steps'; 2 = 'two steps'; 1 = 'one step' }[$NewestTier]
                $Reasons.Add($(if ($NewestReplaces) {
                            "$NewestCredential in the last $NewestWindow days, replacing $($NewestReplaces): looks like a rotation (suspicion $Steps higher)"
                        } else {
                            "$NewestCredential in the last $NewestWindow days (suspicion $Steps higher)"
                        }))
                if ($NewestUsed) {
                    $AppSuspicion++
                    $Reasons.Add("The $($NewestCredential.Substring(0, 1).ToLowerInvariant())$($NewestCredential.Substring(1)) has already signed in (suspicion one step higher)")
                }
            }
            if ($DisabledBy) {
                $AppSuspicion = 4
                $Reasons.Add("Microsoft disabled this app ($DisabledBy): it gets no tokens, but Microsoft found it malicious or abusive. Review what it did and remove it (suspicion Critical)")
            }
            $Risky = $RiskBySpId[$PrincipalId]
            if ($Risky.riskState -eq 'confirmedCompromised') {
                $AppSuspicion = 4
                $Reasons.Add('Identity Protection: an administrator confirmed this service principal compromised (suspicion Critical)')
            } elseif ($Risky.riskLevel -in 'high', 'medium') {
                $Steps = if ($Risky.riskLevel -eq 'high') { 2 } else { 1 }
                $AppSuspicion += $Steps
                $Reasons.Add("Identity Protection rates this service principal at $($Risky.riskLevel) risk$(if ($Risky.riskDetail -and $Risky.riskDetail -ne 'none') { " ($($Risky.riskDetail))" }) (suspicion $(if ($Steps -eq 2) { 'two steps' } else { 'one step' }) higher)")
            }
            # An app owned elsewhere that takes a Microsoft product's name to look trusted on a consent prompt.
            if ($Ownership -in 'Third party', 'Unknown', 'Personal account' -and -not $Sp.verifiedPublisher.displayName -and $DisplayName -match '(?i)\b(microsoft|office ?365|o365|outlook|azure|entra|sharepoint|onedrive|teams|exchange|defender|intune|windows)\b') {
                $Impersonates = $Matches[1]
                $AppSuspicion++
                $Reasons.Add("Named like a Microsoft product ($Impersonates) but neither owned by Microsoft nor from a verified publisher (suspicion one step higher)")
            }
            # The app registration of an app registered here: where sign-in codes and tokens are sent, and who can add a credential.
            if ($AppReg) {
                $SuspectUris = [System.Collections.Generic.List[string]]::new()
                foreach ($RedirectUri in @($AppReg.web.redirectUris) + @($AppReg.spa.redirectUris) + @($AppReg.publicClient.redirectUris)) {
                    $UriObject = $null
                    if (-not $RedirectUri -or -not [uri]::TryCreate([string]$RedirectUri, [System.UriKind]::Absolute, [ref]$UriObject) -or $UriObject.IsLoopback) { continue }
                    if ($UriObject.Scheme -eq 'http' -or $UriObject.HostNameType -in 'IPv4', 'IPv6' -or $UriObject.Host -match '(?i)(^|\.)(ngrok(-free)?\.(io|app|dev)|trycloudflare\.com|loca\.lt|localtunnel\.me|serveo\.net|localhost\.run|pagekite\.me|webhook\.site|requestbin\.(com|net)|pipedream\.net|beeceptor\.com|interact\.sh|oast\.(fun|live|me|online|pro|site))$') {
                        $SuspectUris.Add([string]$RedirectUri)
                    }
                }
                if ($SuspectUris.Count -gt 0) {
                    $AppSuspicion++
                    $Reasons.Add("Redirect URI $($SuspectUris -join ', ') on its app registration uses plain http, a raw IP address or a tunnelling service: sign-in codes and tokens for this app can be sent there (suspicion one step higher)")
                }
                $Owners = @($AppReg.owners | Where-Object { $_ })
                if ($Owners.Count -gt 0) {
                    $OwnerNames = @(foreach ($Owner in $Owners) { if ($Owner.userPrincipalName) { [string]$Owner.userPrincipalName } elseif ($Owner.displayName) { [string]$Owner.displayName } else { [string]$Owner.id } })
                    $Reasons.Add("$($Owners.Count) owner(s) of its app registration ($($OwnerNames -join ', ')) can add a credential and act with all of this access")
                    $GuestOwners = @(foreach ($Owner in $Owners) { if ($Owner.userType -eq 'Guest' -or [string]$Owner.userPrincipalName -like '*#EXT#*') { if ($Owner.userPrincipalName) { [string]$Owner.userPrincipalName } else { [string]$Owner.displayName } } })
                    if ($GuestOwners.Count -gt 0) {
                        $AppSuspicion++
                        $Reasons.Add("Owned by guest account(s) $($GuestOwners -join ', '): someone outside the organisation can add a credential to it (suspicion one step higher)")
                    }
                    $AppOwners = @(foreach ($Owner in $Owners) { if ($Owner.appId -or $Owner.'@odata.type' -eq '#microsoft.graph.servicePrincipal') { [string]$Owner.displayName } })
                    if ($AppOwners.Count -gt 0) {
                        $AppSuspicion++
                        $Reasons.Add("Owned by the app(s) $($AppOwners -join ', '): whoever controls that app can add a credential to this one (suspicion one step higher)")
                    }
                }
                if ($AppReg.signInAudience -in 'AzureADMultipleOrgs', 'AzureADandPersonalMicrosoftAccount') {
                    $Reasons.Add("Registered here for other organisations to use ($($AppReg.signInAudience)): its credentials sign in wherever it is consented$(if ($AppReg.servicePrincipalLockConfiguration.isEnabled -ne $true) { ', and its app instance property lock is off, so an organisation that consents can add credentials to its own copy' })")
                }
            }
            if ($AddedByApp) {
                $AppSuspicion += 2
                $Reasons.Add("$AddedByApp rather than by a person (suspicion two steps higher)")
            }
            if ($Backdated) {
                $AppSuspicion += 2
                $Reasons.Add("$Backdated (suspicion two steps higher)")
            }
            if ($FederatedReasons.Count -gt 0) {
                # Each credential is named; together they raise suspicion by the most any one does.
                foreach ($Flag in $FederatedReasons) { $Reasons.Add($Flag.Text) }
                $AppSuspicion += ($FederatedReasons | Measure-Object -Property Steps -Maximum).Maximum
            } elseif ($FederatedCount -gt 0) {
                $Reasons.Add("$FederatedCount federated credential(s) on its app registration, each trusting a recognised identity provider: tokens it issues for the configured subject sign in as this app with no secret")
            }
            foreach ($Flag in $ActorFlags) { $AppSuspicion += 2; $Reasons.Add($Flag) }
            $Created = $null
            if ($Sp.createdDateTime -is [datetime]) {
                $Created = $Sp.createdDateTime.ToUniversalTime()
            } elseif ($Sp.createdDateTime) {
                $Parsed = [datetimeoffset]::MinValue
                if ([datetimeoffset]::TryParse([string]$Sp.createdDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) { $Created = $Parsed.UtcDateTime }
            }
            if ($Ownership -in 'This tenant', 'Partner tenant', 'Managed identity') {
                if ($Created -and $EffectiveImpact -ge 3 -and ($Now - $Created).TotalDays -le 30) {
                    $AppSuspicion++
                    $Reasons.Add('Added to the tenant in the last 30 days with high-impact permissions (suspicion one step higher)')
                }
            } else {
                # The service principal is created by the first consent; later grants date each added application permission.
                $Grant = $NewestGrant[$PrincipalId]
                $ConsentTier = 0
                $ConsentReason = $null
                foreach ($Candidate in @(
                        @{ When = $Created; Text = 'Consented in this tenant' }
                        @{ When = $Grant.When; Text = "Granted $($Grant.Name)" }
                    )) {
                    if (-not $Candidate.When -or $Candidate.When -gt $Now) { continue }
                    $Age = ($Now - $Candidate.When).TotalDays
                    $Tier = if ($Age -le 7) { 2 } elseif ($Age -le 30) { 1 } else { 0 }
                    if ($Tier -gt $ConsentTier) {
                        $ConsentTier = $Tier
                        $ConsentReason = $Candidate.Text
                    }
                }
                if ($ConsentTier -gt 0) {
                    $AppSuspicion += $ConsentTier
                    $Reasons.Add(('{0} in the last {1} days, an app owned by another organisation (suspicion {2} higher)' -f $ConsentReason, $(if ($ConsentTier -eq 2) { '7' } else { '30' }), $(if ($ConsentTier -eq 2) { 'two steps' } else { 'one step' })))
                }
            }
            $AppSuspicion = [Math]::Min(4, [Math]::Max(1, $AppSuspicion))
            $RiskLevel = $RiskMatrix[$AppSuspicion][$EffectiveImpact]
        }
        if ($Sp -and $Sp.accountEnabled -eq $false -and $RiskLevel -gt 1) {
            $RiskLevel = 1
            $Reasons.Add('Disabled: it cannot sign in or get tokens until someone enables it again')
        }

        $Rows.Add([PSCustomObject]@{
                AppDisplayName                  = $DisplayName
                AppId                           = $AppId
                ServicePrincipalId              = $PrincipalId
                AccountEnabled                  = if ($Sp) { $Sp.accountEnabled } else { $null }
                Ownership                       = $Ownership
                Vendor                          = $Vendor.Name
                VendorCompany                   = $Vendor.Company
                VendorCategory                  = $Vendor.Category
                VendorType                      = $Vendor.VendorType
                VendorWebsite                   = $Vendor.Website
                IsMicrosoftApp                  = $IsMicrosoftApp
                IsPartnerApp                    = $IsPartnerApp
                IsCippApp                       = $IsCippApp
                AppOwnerTenantId                = $OwnerTenantId
                AzureResourceId                 = $AzureResourceId
                PublisherName                   = [string]$Sp.publisherName
                VerifiedPublisher               = [string]$Sp.verifiedPublisher.displayName
                ServicePrincipalType            = [string]$Sp.servicePrincipalType
                SignInAudience                  = [string]$Sp.signInAudience
                CreatedDateTime                 = $Sp.createdDateTime
                SignInActivity                  = $SignInActivity
                LastSignInDateTime              = $LastSignIn
                DaysSinceLastSignIn             = $DaysSinceSignIn
                LastDelegatedSignInDateTime     = $SignIns[1]
                LastAppOnlySignInDateTime       = $SignIns[2]
                LastSignInAsResourceDateTime    = if ($SignIns[3] -and (-not $SignIns[4] -or $SignIns[3] -gt $SignIns[4])) { $SignIns[3] } else { $SignIns[4] }
                SignInActivityTimestamp         = $ActivityTimestamp
                ServicePrincipalCredentialCount = $CredentialCount
                AppRegistrationCredentialCount  = if ($AppReg) { $AppRegCredentialCount } else { $null }
                FederatedCredentialCount        = if ($AppReg -and $null -ne $FederatedByAppId) { $FederatedCount } else { $null }
                CredentialDetails               = $CredentialDetails.ToArray()
                Owners                          = @(foreach ($Owner in @($AppReg.owners | Where-Object { $_ })) { [PSCustomObject]@{ Id = [string]$Owner.id; DisplayName = [string]$Owner.displayName; UserPrincipalName = [string]$Owner.userPrincipalName; UserType = [string]$Owner.userType; AppId = [string]$Owner.appId } })
                DisabledByMicrosoftStatus       = $DisabledBy
                ImpersonatedProduct             = $Impersonates
                IdentityProtectionRiskLevel     = [string]$RiskBySpId[$PrincipalId].riskLevel
                IdentityProtectionRiskState     = [string]$RiskBySpId[$PrincipalId].riskState
                Risk                            = $RankName[$RiskLevel]
                RiskReasons                     = $Reasons.ToArray()
                Suspicion                       = $RankName[$AppSuspicion]
                HighestImpact                   = $RankName[$MaxImpact]
                Categories                      = $Categories.ToArray()
                PermissionCount                 = $Details.Count
                ApplicationPermissionCount      = $ApplicationCount
                DelegatedPermissionCount        = $Details.Count - $ApplicationCount - $RoleCount - $ExchangeRoleCount
                DirectoryRoleCount              = $RoleCount
                ExchangeRoleCount               = $ExchangeRoleCount
                HasAllPrincipalsGrant           = $HasAllPrincipals
                Permissions                     = $Labels -join '; '
                PermissionDetails               = $Details
                CacheTimestamp                  = $CacheTimestamp
            })
    }

    $Output = $Rows.ToArray()
    $SortKeys = [string[]]::new($Output.Count)
    for ($i = 0; $i -lt $Output.Count; $i++) {
        $Row = $Output[$i]
        $SortKeys[$i] = '{0}|{1}|{2}|{3}|{4}' -f (5 - [int]$RiskRank[[string]$Row.Risk]), (5 - [int]$RiskRank[[string]$Row.HighestImpact]), (5 - [int]$RiskRank[[string]$Row.Suspicion]), $Row.AppDisplayName, $Row.ServicePrincipalId
    }
    [Array]::Sort[string, object]($SortKeys, $Output, [System.StringComparer]::OrdinalIgnoreCase)
    return $Output
}
