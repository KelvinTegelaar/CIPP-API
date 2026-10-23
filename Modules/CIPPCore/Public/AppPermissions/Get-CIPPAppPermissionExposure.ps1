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
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [switch]$Live,
        [switch]$ExcludeDelegated,
        [switch]$SkipSignInActivity,
        [string]$ServicePrincipalId
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

    $ApiByAppId = @{
        '00000003-0000-0000-c000-000000000000' = 'Microsoft Graph'
        '00000003-0000-0ff1-ce00-000000000000' = 'SharePoint Online'
        '00000002-0000-0ff1-ce00-000000000000' = 'Exchange Online'
    }
    $ApiByDisplayName = @{
        'Microsoft Graph'              = 'Microsoft Graph'
        'Office 365 SharePoint Online' = 'SharePoint Online'
        'Office 365 Exchange Online'   = 'Exchange Online'
    }
    $SpFields = @('id', 'appId', 'displayName', 'appOwnerOrganizationId', 'accountEnabled', 'publisherName', 'verifiedPublisher', 'servicePrincipalType', 'signInAudience', 'createdDateTime', 'passwordCredentials', 'keyCredentials', 'preferredSingleSignOnMode')
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
            if ($Count.Timestamp -and (-not $CacheTimestamp -or $Count.Timestamp -lt $CacheTimestamp)) { $CacheTimestamp = $Count.Timestamp }
        }

        $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals' -Rows $RawRows['ServicePrincipals'] -Fields $SpFields)
        $Assignments = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'AppRoleAssignments' -Rows $RawRows['AppRoleAssignments'] -Fields 'principalId', 'resourceId', 'resourceDisplayName', 'appRoleId', 'servicePrincipalDisplayName', 'servicePrincipalAppId')
        $Grants = if ($ExcludeDelegated) { @() } else { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -Rows $RawRows['OAuth2PermissionGrants'] -Fields 'clientId', 'resourceId', 'consentType', 'scope') }
    }

    # No service principals means the tenant has not synced: nothing can be checked.
    if ($ServicePrincipals.Count -eq 0) {
        throw [System.Management.Automation.ItemNotFoundException]::new("No service principals are available for $TenantFilter yet. Run a cache sync first.")
    }

    $Catalog = Get-CIPPRiskyPermissionCatalog
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
                Api         = $Entry.api
                Name        = $Entry.name
                Type        = 'Delegated'
                Suspicion   = $Entry.suspicion
                Impact      = $Entry.impact
                Categories  = @($Entry.categories)
                Reason      = $Entry.reason
                ConsentType = $ConsentType
            }
        }
    }

    $CippAppId = [System.Environment]::GetEnvironmentVariable('ApplicationID')
    $PartnerTenantId = [System.Environment]::GetEnvironmentVariable('TenantID')
    $VendorTenants = Get-CIPPVendorTenantMap

    if ($ServicePrincipalId) {
        $Only = $null
        [void]$PermissionsByApp.TryGetValue($ServicePrincipalId, [ref]$Only)
        $PermissionsByApp = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Only) { $PermissionsByApp[$ServicePrincipalId] = $Only }
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
            $ActivityTimestamp = $ActivityCount.Timestamp
            $ActivityByAppId = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            if ($ActivityRows.Count -gt 0) {
                foreach ($Item in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities' -Rows $ActivityRows.ToArray() -Fields (@('appId') + $ActivityFields))) {
                    if ($Item.appId) { $ActivityByAppId[[string]$Item.appId] = $Item }
                }
            }
        }
    }
    $Now = [datetime]::UtcNow

    foreach ($Pair in $PermissionsByApp.GetEnumerator()) {
        $PrincipalId = $Pair.Key
        $Sp = $null
        [void]$SpById.TryGetValue($PrincipalId, [ref]$Sp)
        $Fallback = $FallbackApps[$PrincipalId]
        $AppId = if ($Sp) { [string]$Sp.appId } else { [string]$Fallback.servicePrincipalAppId }
        $DisplayName = if ($Sp.displayName) { [string]$Sp.displayName } elseif ($Fallback.servicePrincipalDisplayName) { [string]$Fallback.servicePrincipalDisplayName } else { $PrincipalId }
        $OwnerTenantId = [string]$Sp.appOwnerOrganizationId
        $Vendor = $null
        if ($OwnerTenantId) { [void]$VendorTenants.TryGetValue($OwnerTenantId, [ref]$Vendor) }
        $IsMicrosoftApp = [bool]($Vendor -and $Vendor.VendorType -eq 'Microsoft')
        $IsPartnerApp = [bool]($PartnerTenantId -and $OwnerTenantId -eq $PartnerTenantId)
        $Ownership = if (-not $OwnerTenantId) {
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
        $CredentialCount = 0
        foreach ($Credential in $Sp.passwordCredentials) { $CredentialCount++ }
        foreach ($Credential in $Sp.keyCredentials) { $CredentialCount++ }

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
        }
        # Explicit type arguments: without them PowerShell sorts a copy of the items array.
        [Array]::Sort[string, object]($DetailKeys, $Details, [System.StringComparer]::OrdinalIgnoreCase)

        $Labels = [string[]]::new($Details.Count)
        for ($i = 0; $i -lt $Details.Count; $i++) {
            $D = $Details[$i]
            $Labels[$i] = if ($D.ConsentType) {
                '{0}: {1} ({2}, suspicion {3}, impact {4}, {5})' -f $D.Api, $D.Name, $D.Type, $D.Suspicion, $D.Impact, $D.ConsentType
            } else {
                '{0}: {1} ({2}, suspicion {3}, impact {4})' -f $D.Api, $D.Name, $D.Type, $D.Suspicion, $D.Impact
            }
        }
        $Categories = [System.Collections.Generic.List[string]]::new()
        foreach ($Category in $CategoryOrder) { if ($CategorySet.Contains($Category)) { $Categories.Add($Category) } }

        # Context-aware rating: the permissions' suspicion moved by who owns the app and how it looks here, crossed with impact.
        $IsCippApp = [bool]($CippAppId -and $AppId -eq $CippAppId)
        $Reasons = [System.Collections.Generic.List[string]]::new()
        $Reasons.Add(('Permissions: highest impact {0}, highest suspicion {1}' -f $RankName[$MaxImpact], $RankName[$MaxSuspicion]))
        $AppSuspicion = $MaxSuspicion
        $EffectiveImpact = $MaxImpact
        if ($ApplicationCount -eq 0 -and -not $HasAllPrincipals -and $EffectiveImpact -gt 1) {
            $EffectiveImpact--
            $Reasons.Add('Only delegated permissions, each consented by individual users: limited to what those users can reach (impact one step lower)')
        }
        $RiskLevel = 0
        if ($IsCippApp) {
            $AppSuspicion = 1
            $RiskLevel = 1
            $Reasons.Add("CIPP's own app: its exposure is the security of your partner tenant")
        } elseif ($IsMicrosoftApp) {
            $AppSuspicion = 1
            $RiskLevel = 1
            $Reasons.Add('Microsoft first-party app')
        } else {
            switch ($Ownership) {
                'Partner tenant' {
                    $AppSuspicion--
                    $Reasons.Add('Registered in your partner tenant (suspicion one step lower); a compromise there reaches this access in every client that consented')
                }
                'MSP vendor' { $AppSuspicion--; $Reasons.Add("Known MSP vendor $($Vendor.Name) (suspicion one step lower)") }
                'Known vendor' { $AppSuspicion--; $Reasons.Add("Known vendor $($Vendor.Name) (suspicion one step lower)") }
                'This tenant' { $Reasons.Add('Registered in this tenant: its credentials are managed here') }
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
            # SAML apps keep their token signing certificate on the service principal.
            if ($CredentialCount -gt 0 -and $Ownership -ne 'This tenant' -and [string]$Sp.preferredSingleSignOnMode -ne 'saml') {
                $AppSuspicion += 2
                $Reasons.Add("$CredentialCount credential(s) on its service principal in this tenant, a known persistence technique for apps owned elsewhere (suspicion two steps higher)")
            }
            $Created = $null
            if ($Sp.createdDateTime -is [datetime]) {
                $Created = $Sp.createdDateTime.ToUniversalTime()
            } elseif ($Sp.createdDateTime) {
                $Parsed = [datetimeoffset]::MinValue
                if ([datetimeoffset]::TryParse([string]$Sp.createdDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) { $Created = $Parsed.UtcDateTime }
            }
            if ($Created -and $EffectiveImpact -ge 3 -and ($Now - $Created).TotalDays -le 30) {
                $AppSuspicion++
                $Reasons.Add('Added to the tenant in the last 30 days with high-impact permissions (suspicion one step higher)')
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
                Risk                            = $RankName[$RiskLevel]
                RiskReasons                     = $Reasons.ToArray()
                Suspicion                       = $RankName[$AppSuspicion]
                HighestImpact                   = $RankName[$MaxImpact]
                Categories                      = $Categories.ToArray()
                PermissionCount                 = $Details.Count
                ApplicationPermissionCount      = $ApplicationCount
                DelegatedPermissionCount        = $Details.Count - $ApplicationCount
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
