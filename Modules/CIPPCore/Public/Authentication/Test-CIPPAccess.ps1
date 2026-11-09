function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList,
        [switch]$GroupList,
        # Tenants or tenant-group selectors to check instead of the ones the request names; checked even on AnyTenant endpoints
        $TenantFilter,
        # Internal: the role's tenant list before a requested tenant group narrows it
        [switch]$IgnoreTenantGroup
    )
    # A requested tenant group narrows the tenant list to the caller's tenants in that group, so the router's
    # request scope and every endpoint that asks for the list follow the group
    if ($TenantList.IsPresent -and $Request.Query.tenantGroup -and -not $IgnoreTenantGroup.IsPresent) {
        $RoleTenants = @(Test-CIPPAccess -Request $Request -TenantList -IgnoreTenantGroup)
        $Members = @(@(Expand-CIPPTenantGroups -TenantFilter @([PSCustomObject]@{ type = 'Group'; value = $Request.Query.tenantGroup })).addedFields.customerId | Where-Object { $_ })
        if ($RoleTenants -contains 'AllTenants') { return $Members }
        return @($Members.Where({ $RoleTenants -contains $_ }))
    }
    # Initialize per-call profiling
    $AccessTimings = @{}
    $AccessTotalSw = [System.Diagnostics.Stopwatch]::StartNew()

    # Request-local identity context, read by New-CippCoreRequest for its per-request
    # access log line. Reset here so a denied call never reports the previous caller.
    $script:CippAccessUserContext = $null
    # Request-local impersonation marker; reset so it never leaks between requests.
    $script:CippImpersonation = $null

    # Get function help
    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint

    $SwPermissions = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $script:CIPPFunctionPermissions) {
        if ($global:CIPPFunctionPermissions) {
            $script:CIPPFunctionPermissions = $global:CIPPFunctionPermissions
        } else {
            $PermissionsFileJson = Join-Path $env:CIPPRootPath 'Config\function-permissions.json'

            if (Test-Path $PermissionsFileJson) {
                try {
                    $script:CIPPFunctionPermissions = [System.IO.File]::ReadAllText($PermissionsFileJson) | ConvertFrom-Json -AsHashtable
                    Write-Debug "Loaded $($script:CIPPFunctionPermissions.Count) function permissions from JSON cache"
                } catch {
                    Write-Warning "Failed to load function permissions from JSON: $($_.Exception.Message)"
                }
            }
        }
    }
    $SwPermissions.Stop()
    $AccessTimings['FunctionPermissions'] = $SwPermissions.Elapsed.TotalMilliseconds

    if ($FunctionName -ne 'Invoke-me') {
        $swHelp = [System.Diagnostics.Stopwatch]::StartNew()
        if ($script:CIPPFunctionPermissions -and $script:CIPPFunctionPermissions.ContainsKey($FunctionName)) {
            $PermissionData = $script:CIPPFunctionPermissions[$FunctionName]
            $APIRole = $PermissionData['Role']
            $Functionality = $PermissionData['Functionality']
            if ($DebugPreference -ne 'SilentlyContinue') { Write-Debug "Loaded function permission data from cache for '$FunctionName': Role='$APIRole', Functionality='$Functionality'" }
        } else {
            try {
                $Help = Get-Help $FunctionName -ErrorAction Stop
                $APIRole = $Help.Role
                $Functionality = $Help.Functionality
                Write-Debug "Loaded function permission data via Get-Help for '$FunctionName': Role='$APIRole', Functionality='$Functionality'"
            } catch {
                Write-Warning "Function '$FunctionName' not found"
            }
        }
        $swHelp.Stop()
        $AccessTimings['GetHelp'] = $swHelp.Elapsed.TotalMilliseconds
    }

    # A tenant group runs the endpoint's All Tenants path narrowed to the group, so only an endpoint whose All Tenants
    # path honours the request scope may accept one, by declaring '.FUNCTIONALITY Entrypoint,TenantGroup'.
    $TenantGroup = $Request.Query.tenantGroup
    if ($TenantGroup -and -not $TenantList.IsPresent -and -not $GroupList.IsPresent -and -not $PSBoundParameters.ContainsKey('TenantFilter')) {
        if ($Functionality -notmatch '\bTenantGroup\b') {
            $Message = if ($APIRole -like '*.Read') { "This view doesn't support tenant groups. Pick a tenant or All Tenants." } else { 'A tenant group can only be used to view data. Pick a single tenant to make changes.' }
            throw [System.ArgumentException]::new($Message)
        }
    }

    # Get default roles from config (cache per runspace for performance)
    $swRolesLoad = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $script:CIPPBaseRoles) {
        $script:CIPPBaseRoles = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\cipp-roles.json')) | ConvertFrom-Json
    }
    $swRolesLoad.Stop()
    $AccessTimings['LoadBaseRoles'] = $swRolesLoad.Elapsed.TotalMilliseconds
    $DefaultRoles = @('superadmin', 'admin', 'editor', 'readonly', 'anonymous', 'authenticated')

    if ($APIRole -eq 'Public') {
        return $true
    }

    if ($Request.Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Request.Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        $Type = 'APIClient'
        $swApiClient = [System.Diagnostics.Stopwatch]::StartNew()
        # Direct API Access
        $IPAddress = Get-CippRequestIPAddress -Request $Request

        $Client = Get-CippApiClient -AppId $Request.Headers.'x-ms-client-principal-name'
        if ($Client) {
            Write-Information "API Access: AppName=$($Client.AppName), AppId=$($Request.Headers.'x-ms-client-principal-name'), IP=$IPAddress"
            # Set before the IP check so an IP-range denial is still attributed to the client
            $script:CippAccessUserContext = [PSCustomObject]@{
                User  = "$($Client.AppName) ($IPAddress)"
                Roles = @($Client.Role ?? 'cipp-api')
            }
            $IPMatched = $false
            if ($Client.IPRange -notcontains 'Any') {
                foreach ($Range in $Client.IPRange) {
                    if ($IPaddress -eq $Range -or (Test-IpInRange -IPAddress $IPAddress -Range $Range)) {
                        $IPMatched = $true
                        break
                    }
                }
            } else {
                $IPMatched = $true
            }

            if ($IPMatched) {
                if ($Client.Role) {
                    $CustomRoles = $Client.Role | ForEach-Object {
                        if ($DefaultRoles -notcontains $_) {
                            $_
                        }
                    }
                    $BaseRole = Find-CippBaseRole -Roles $Client.Role -BaseRoles $script:CIPPBaseRoles
                } else {
                    $CustomRoles = @('cipp-api')
                }
            } else {
                throw 'Access to this CIPP API endpoint is not allowed, the API Client does not have the required permission'
            }
        } else {
            $CustomRoles = @('cipp-api')
            Write-Information "API Access: AppId=$($Request.Headers.'x-ms-client-principal-name'), IP=$IPAddress"
            $script:CippAccessUserContext = [PSCustomObject]@{
                User  = "AppId $($Request.Headers.'x-ms-client-principal-name') ($IPAddress)"
                Roles = @('cipp-api')
            }
        }
        if ($Request.Params.CIPPEndpoint -eq 'me') {
            $Permissions = Get-CippAllowedPermissions -UserRoles $CustomRoles
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = (
                        @{
                            'clientPrincipal' = @{
                                appId   = $Request.Headers.'x-ms-client-principal-name'
                                appRole = $CustomRoles
                            }
                            'permissions'     = @($Permissions)
                        } | ConvertTo-Json -Depth 5)
                })
        }
        $swApiClient.Stop()
        $AccessTimings['ApiClientBranch'] = $swApiClient.Elapsed.TotalMilliseconds

    } else {
        $Type = 'User'
        $swUserBranch = [System.Diagnostics.Stopwatch]::StartNew()
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

        if ($User.claims -and [string]::IsNullOrWhiteSpace($User.userDetails)) {
            $Claims = @($User.claims)
            $Upn = ($Claims | Where-Object { $_.typ -in @('preferred_username', 'upn', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn', 'email', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') } | Select-Object -First 1).val
            if ([string]::IsNullOrWhiteSpace($Upn)) { $Upn = $Request.Headers.'x-ms-client-principal-name' }
            $Oid = ($Claims | Where-Object { $_.typ -in @('http://schemas.microsoft.com/identity/claims/objectidentifier', 'oid') } | Select-Object -First 1).val
            $User = [pscustomobject]@{
                identityProvider = 'aad'
                userId           = $Oid
                userDetails      = $Upn
                userRoles        = @('authenticated', 'anonymous')
            }
        }

        # Check for roles granted via group membership
        if (($User.userRoles | Measure-Object).Count -eq 2 -and $User.userRoles -contains 'authenticated' -and $User.userRoles -contains 'anonymous') {
            $swResolveUserRoles = [System.Diagnostics.Stopwatch]::StartNew()
            $User = Test-CIPPAccessUserRole -User $User
            $swResolveUserRoles.Stop()
            $AccessTimings['ResolveUserRoles'] = $swResolveUserRoles.Elapsed.TotalMilliseconds
        }

        $swIPCheck = [System.Diagnostics.Stopwatch]::StartNew()
        if (-not $User.userRoles) {
            throw 'Access denied: unable to resolve roles for the authenticated principal'
        }

        # IP enforcement deliberately uses the REAL roles, never the impersonated one: a
        # role's IP allowlist describes where its actual members sign in from, and
        # simulating it locks the impersonating superadmin out of the entire UI, /me and
        # the exit banner included.
        $AllowedIPRanges = Get-CIPPRoleIPRanges -Roles $User.userRoles

        if ($AllowedIPRanges -notcontains 'Any') {
            $IPAddress = Get-CippRequestIPAddress -Request $Request
            if ($IPAddress) {
                $IPAllowed = $false
                foreach ($Range in $AllowedIPRanges) {
                    if ($IPAddress -eq $Range -or (Test-IpInRange -IPAddress $IPAddress -Range $Range)) {
                        $IPAllowed = $true
                        break
                    }
                }

                if ((-not $IPAllowed) -and ($Request.Params.CIPPEndpoint -ne 'me')) {
                    throw "Access to this CIPP API endpoint is not allowed, your IP address ($IPAddress) is not in the allowed range for your role(s)"
                }
            } else {
                $IPAllowed = $true
            }
        } else {
            $IPAllowed = $true
        }

        $swIPCheck.Stop()
        $AccessTimings['IPRangeCheck'] = $swIPCheck.Elapsed.TotalMilliseconds

        # Superadmin-only role impersonation: everything downstream (/me permissions,
        # base/custom role checks, tenant scoping) evaluates under the impersonated role.
        # Only the IP check above is exempt, so impersonation can never lock the UI.
        $Impersonation = Resolve-CippImpersonation -User $User -Request $Request
        $User = $Impersonation.User
        if ($Impersonation.Impersonating) {
            $script:CippImpersonation = $Impersonation
        }

        $script:CippAccessUserContext = [PSCustomObject]@{
            User  = if ($Impersonation.Impersonating) { "$($User.userDetails) (impersonating $($Impersonation.Impersonating))" } else { $User.userDetails }
            Roles = @($User.userRoles | Where-Object { $_ -notin @('anonymous', 'authenticated') })
        }

        if ($Request.Params.CIPPEndpoint -eq 'me') {
            # Impersonation marker passed explicitly rather than read from script scope inside the helper.
            return (New-CippMeResponse -User $User -IPAllowed $IPAllowed -IPAddress $IPAddress -Impersonation $script:CippImpersonation -AccessTimings $AccessTimings)
        }

        if ($User.userRoles -contains 'admin' -or $User.userRoles -contains 'superadmin') {
            if ($TenantList.IsPresent) {
                return @('AllTenants')
            }
            if ($GroupList.IsPresent) {
                return @('AllGroups')
            }
        }

        $CustomRoles = $User.userRoles | ForEach-Object {
            if ($DefaultRoles -notcontains $_) {
                $_
            }
        }

        $BaseRole = $null

        if ($User.userRoles -contains 'superadmin') {
            $User.userRoles = @('superadmin')
        } elseif ($User.userRoles -contains 'admin') {
            $User.userRoles = @('admin')
        }
        $BaseRole = Find-CippBaseRole -Roles $User.userRoles -BaseRoles $script:CIPPBaseRoles

    }

    # Check base role permissions before continuing to custom roles
    if ($null -ne $BaseRole) {
        $BaseRoleAllowed = $false
        foreach ($Include in $BaseRole.Value.include) {
            if ($APIRole -like $Include) {
                $BaseRoleAllowed = $true
                break
            }
        }
        foreach ($Exclude in $BaseRole.Value.exclude) {
            if ($APIRole -like $Exclude) {
                $BaseRoleAllowed = $false
                break
            }
        }
        if (!$BaseRoleAllowed) {
            throw "Access to this CIPP API endpoint is not allowed, the '$($BaseRole.Name)' base role does not have the required permission: $APIRole"
        }
    }

    # Check custom role permissions for limitations on api calls or tenants
    if ($null -eq $BaseRole.Name -and $Type -eq 'User' -and ($CustomRoles | Measure-Object).Count -eq 0) {
        throw 'Access to this CIPP API endpoint is not allowed, the user does not have the required permission'
    } elseif (($CustomRoles | Measure-Object).Count -gt 0) {
        if (@('admin', 'superadmin') -contains $BaseRole.Name) {
            return $true
        } else {
            # Scope-only requests resolve from the cached rules. On a warm cache this needs no
            # storage read at all, and it only needs the tenant table when a rule actually says
            # 'all tenants except', because that is the one case where the answer depends on
            # which tenants currently exist.
            if ($TenantList.IsPresent -or $GroupList.IsPresent) {
                $swScopeRules = [System.Diagnostics.Stopwatch]::StartNew()
                $ScopeRules = foreach ($CustomRole in $CustomRoles) {
                    try {
                        Get-CippAccessScopeRule -Role $CustomRole
                    } catch {
                        Write-Information $_.Exception.Message
                    }
                }
                $swScopeRules.Stop()
                $AccessTimings['GetScopeRules'] = $swScopeRules.Elapsed.TotalMilliseconds

                # The scope belongs to the endpoint being called: only roles that grant its
                # permission contribute, and a granting role that blocks it takes away every
                # tenant (or group) it reaches - the same rules as the per-request decision.
                $Endpoint = $Request.Params.CIPPEndpoint
                $GrantingRules = @(foreach ($Rule in $ScopeRules) { if (-not $APIRole -or @($Rule.Permissions).Where({ $_ -match $APIRole }, 'First').Count -gt 0) { $Rule } })
                $AllowingRules = @($GrantingRules.Where({ $_.BlockedEndpoints -notcontains $Endpoint }))
                $BlockingRules = @($GrantingRules.Where({ $_.BlockedEndpoints -contains $Endpoint }))

                if ($AllowingRules.Count -eq 0 -or $BlockingRules.Where({ $_.Unrestricted }, 'First').Count -gt 0) {
                    # No role grants this endpoint anywhere it is not blocked: entitled to nothing
                    return @()
                }

                if ($TenantList.IsPresent) {
                    $swTenantList = [System.Diagnostics.Stopwatch]::StartNew()
                    $AnyUnrestricted = $AllowingRules.Where({ $_.Unrestricted }, 'First').Count -gt 0
                    if ($AnyUnrestricted -and $BlockingRules.Count -eq 0) {
                        return @('AllTenants')
                    }
                    $NeedsTenantList = $AnyUnrestricted -or $GrantingRules.Where({ -not $_.Unrestricted -and $_.AllowAllTenants }, 'First').Count -gt 0
                    $Tenants = if ($NeedsTenantList) { Get-Tenants -IncludeErrors } else { @() }

                    $Reach = {
                        param($Rule)
                        if ($Rule.Unrestricted) { return $Tenants.customerId }
                        $AllowedForRule = if ($Rule.AllowAllTenants) { $Tenants.customerId } else { $Rule.AllowedTenants }
                        @($AllowedForRule).Where({ $Rule.BlockedTenants -notcontains $_ })
                    }
                    $Blocked = @(foreach ($Rule in $BlockingRules) { & $Reach $Rule })
                    $LimitedTenantList = foreach ($Rule in $AllowingRules) {
                        @(& $Reach $Rule).Where({ $Blocked -notcontains $_ })
                    }
                    $swTenantList.Stop()
                    $AccessTimings['BuildTenantList'] = $swTenantList.Elapsed.TotalMilliseconds
                    return @($LimitedTenantList | Sort-Object -Unique)
                }

                Write-Information "Getting allowed groups for roles: $($CustomRoles -join ', ')"
                $swGroupList = [System.Diagnostics.Stopwatch]::StartNew()
                $BlockedGroups = @($BlockingRules.AllowedGroups)
                $LimitedGroupList = foreach ($Rule in $AllowingRules) {
                    if ($Rule.Unrestricted -and $BlockingRules.Count -eq 0) { @('AllGroups') } else { @($Rule.AllowedGroups).Where({ $BlockedGroups -notcontains $_ }) }
                }
                $swGroupList.Stop()
                $AccessTimings['BuildGroupList'] = $swGroupList.Elapsed.TotalMilliseconds
                return @($LimitedGroupList | Sort-Object -Unique)
            }

            $swTenantsLoad = [System.Diagnostics.Stopwatch]::StartNew()
            $Tenants = Get-Tenants -IncludeErrors
            $swTenantsLoad.Stop()
            $AccessTimings['LoadTenants'] = $swTenantsLoad.Elapsed.TotalMilliseconds
            $PermissionsFound = $false
            $swRolePerms = [System.Diagnostics.Stopwatch]::StartNew()
            $PermissionSet = foreach ($CustomRole in $CustomRoles) {
                try {
                    Get-CIPPRolePermissions -Role $CustomRole
                    $PermissionsFound = $true
                } catch {
                    Write-Information $_.Exception.Message
                }
            }
            $swRolePerms.Stop()
            $AccessTimings['GetRolePermissions'] = $swRolePerms.Elapsed.TotalMilliseconds

            if ($PermissionsFound) {
                # Tenant list and group list requests have already returned above, from the
                # cached scope rules. Everything from here is the per-endpoint access decision.
                # Every tenant the request names is a target, wherever it is named: an endpoint
                # may act on the body while the query names another tenant. Do not fall back to
                # $env:TenantID - that is the partner/home tenant, not a customer. No target means
                # the endpoint is not tenant-scoped; a target that resolves to no known tenant is
                # denied on the allow pass and stays in scope for the block pass.
                $Targets = [System.Collections.Generic.List[object]]::new()
                $ExplicitTargets = $PSBoundParameters.ContainsKey('TenantFilter')
                $GroupTarget = if ($TenantGroup -and -not $ExplicitTargets) { [PSCustomObject]@{ type = 'Group'; value = $TenantGroup; label = (Get-TenantGroups -GroupId $TenantGroup).Name } }
                $Sources = if ($ExplicitTargets) { @(, $TenantFilter) } else { @(($GroupTarget ?? $Request.Query.tenantFilter), $Request.Body.tenantFilter, $Request.Query.tenantId, $Request.Body.tenantId) }
                foreach ($Named in $Sources) {
                    foreach ($Item in @($Named)) {
                        if ($null -eq $Item) { continue }
                        # A selector without .value stays a target (unresolvable, so denied) rather than vanishing.
                        $Id = if ($Item -is [string]) { $Item } elseif ($null -ne $Item.value) { "$($Item.value)" } else { "$Item" }
                        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
                        $IsGroup = $Item -isnot [string] -and $Item.type -eq 'Group'
                        if ($Targets.Where({ $_.Id -eq $Id -and $_.IsGroup -eq $IsGroup }).Count -eq 0) {
                            # Messages name a tenant by its domain and a group by the label the caller sent.
                            $Name = if ($IsGroup) { "the tenant group '$(if ($Item.label) { $Item.label } else { $Id })'" } elseif ($Id -eq 'AllTenants') { 'all tenants' } else { $Tenants.Where({ $_.customerId -eq $Id -or $_.defaultDomainName -eq $Id }, 'First')[0].defaultDomainName ?? $Id }
                            $Targets.Add([PSCustomObject]@{ Id = $Id; IsGroup = $IsGroup; Name = $Name; Selector = [object]::ReferenceEquals($Item, $GroupTarget) })
                        }
                    }
                }
                if ($Targets.Count -eq 0) { $Targets.Add([PSCustomObject]@{ Id = $null; IsGroup = $false }) }
                $swPermissionEval = [System.Diagnostics.Stopwatch]::StartNew()

                # Only a role that grants the endpoint's permission can allow or block it, and it
                # has to cover the tenant itself: a permission from one role never combines with
                # another role's tenants, so the order the roles arrive in cannot change the answer.
                $GrantingRoles = @(foreach ($Role in $PermissionSet) { if (@($Role.Permissions).Where({ $_ -match $APIRole }, 'First').Count -gt 0) { $Role } })
                if ($GrantingRoles.Count -eq 0) {
                    throw "Access to this CIPP API endpoint is not allowed, you do not have the required permission: $APIRole"
                }

                # Block pass: deny wins wherever a granting role that blocks this endpoint reaches.
                # -TreatUnresolvedAsInScope keeps unresolved targets in scope (fail closed).
                foreach ($Role in $GrantingRoles) {
                    if ($Role.BlockedEndpoints -notcontains $Request.Params.CIPPEndpoint) { continue }
                    foreach ($Target in $Targets) {
                        if (Test-CippRoleTenantScope -Role $Role -TenantFilter $Target.Id -IsGroup:$Target.IsGroup -Tenants $Tenants -ApiRole $APIRole -TreatUnresolvedAsInScope) {
                            throw "Your role '$($Role.Role)' blocks $($Request.Params.CIPPEndpoint)$(if ($Target.Id) { " on $($Target.Name)" })."
                        }
                    }
                }

                # Allow pass: every target needs a granting role that covers it.
                $TenantAllowed = $true
                $DeniedTarget = $null
                foreach ($Target in $Targets) {
                    $Covered = $false
                    foreach ($Role in $GrantingRoles) {
                        if (Test-CippRoleTenantScope -Role $Role -TenantFilter $Target.Id -IsGroup:$Target.IsGroup -TenantSelector:$Target.Selector -Tenants $Tenants -ApiRole $APIRole) {
                            $Covered = $true
                            break
                        }
                    }
                    if (-not $Covered) {
                        $TenantAllowed = $false
                        $DeniedTarget = $Target
                        break
                    }
                }
                $swPermissionEval.Stop()
                $AccessTimings['EvaluatePermissions'] = $swPermissionEval.Elapsed.TotalMilliseconds

                if (!$TenantAllowed -and ($Functionality -notmatch 'AnyTenant' -or $ExplicitTargets -or $GroupTarget)) {
                    # Say why, naming only the tenant the caller asked for and roles they hold. A tenant that
                    # does not exist reads the same as one outside every role, so this cannot list tenants.
                    $Name = $DeniedTarget.Name
                    $Known = $DeniedTarget.IsGroup -or $Tenants.Where({ $_.customerId -eq $DeniedTarget.Id -or $_.defaultDomainName -eq $DeniedTarget.Id }, 'First').Count -gt 0
                    $GrantsGroup = { param($Role) @($Role.AllowedTenants).Where({ $_ -is [PSCustomObject] -and $_.type -eq 'Group' -and $_.value -eq $DeniedTarget.Id }, 'First').Count -gt 0 }
                    $Excluding = if (-not $Known) {
                        $null
                    } elseif (-not $DeniedTarget.IsGroup -and $DeniedTarget.Id -ne 'AllTenants') {
                        $GrantingRoles.Where({ (Test-CippRoleTenantScope -Role ([PSCustomObject]@{ AllowedTenants = $_.AllowedTenants; BlockedTenants = @() }) -TenantFilter $DeniedTarget.Id -Tenants $Tenants -ApiRole $APIRole) }, 'First')[0]
                    } elseif ($DeniedTarget.IsGroup) {
                        $GrantingRoles.Where({ & $GrantsGroup $_ }, 'First')[0]
                    }
                    $Covering = if ($Known -and $DeniedTarget.Id -ne 'AllTenants') {
                        @($PermissionSet.Where({ $GrantingRoles -notcontains $_ -and $(if ($DeniedTarget.IsGroup) { & $GrantsGroup $_ } else { Test-CippRoleTenantScope -Role $_ -TenantFilter $DeniedTarget.Id -Tenants $Tenants -ApiRole $APIRole }) }))
                    }
                    $ReadPermission = $APIRole -replace '\.ReadWrite$', '.Read'
                    $CanView = $APIRole -like '*.ReadWrite' -and @($Covering).Where({ @($_.Permissions).Where({ $_ -match $ReadPermission }, 'First').Count -gt 0 }, 'First').Count -gt 0
                    $Message = if ($DeniedTarget.Selector -and $GrantingRoles.Where({ $_.BlockTenantGroups }, 'First').Count -gt 0) {
                        "Your roles don't allow viewing a tenant group. Pick a tenant instead, or ask an admin to change your roles."
                    } elseif ($DeniedTarget.Id -eq 'AllTenants') {
                        "Your roles don't allow this on all tenants at once. Pick a tenant instead, or ask an admin to change your roles."
                    } elseif ($Excluding) {
                        if ($DeniedTarget.IsGroup) { "Your role '$($Excluding.Role)' excludes a tenant in $Name." } else { "Your role '$($Excluding.Role)' excludes $Name." }
                    } elseif ($CanView) {
                        "You can view $Name but not change it. This action needs $APIRole, which your roles don't grant for $(if ($DeniedTarget.IsGroup) { 'that group' } else { 'that tenant' })."
                    } elseif (@($Covering).Count -gt 0) {
                        "Your roles include $Name, but not the $APIRole permission this action needs there."
                    } else {
                        "Your roles don't include $Name. Ask an admin to add it to one of your roles."
                    }
                    throw $Message
                } else {
                    return $true
                }
            } else {
                # No permissions found for any roles
                if ($TenantList.IsPresent) {
                    return @()
                }
                throw 'Access to this CIPP API endpoint is not allowed, the user does not have the required permission'
            }
        } else {
            # No permissions found for any roles
            if ($TenantList.IsPresent) {
                return @()
            }
            throw 'Access to this CIPP API endpoint is not allowed, the user does not have the required permission'
        }
    }

    if ($TenantList.IsPresent) {
        $AccessTotalSw.Stop()
        $AccessTimings['Total'] = $AccessTotalSw.Elapsed.TotalMilliseconds
        if ($DebugPreference -ne 'SilentlyContinue') {
            $AccessTimingsRounded = [ordered]@{}
            foreach ($Key in ($AccessTimings.Keys | Sort-Object)) { $AccessTimingsRounded[$Key] = [math]::Round($AccessTimings[$Key], 2) }
            Write-Debug "#### Access Timings #### $($AccessTimingsRounded | ConvertTo-Json -Compress)"
        }
        return @('AllTenants')
    }
    # A built-in role with no custom role limiting it sees every group, as it sees every tenant.
    if ($GroupList.IsPresent) {
        return @('AllGroups')
    }
    $AccessTotalSw.Stop()
    $AccessTimings['Total'] = $AccessTotalSw.Elapsed.TotalMilliseconds
    if ($DebugPreference -ne 'SilentlyContinue') {
        $AccessTimingsRounded = [ordered]@{}
        foreach ($Key in ($AccessTimings.Keys | Sort-Object)) { $AccessTimingsRounded[$Key] = [math]::Round($AccessTimings[$Key], 2) }
        Write-Debug "#### Access Timings #### $($AccessTimingsRounded | ConvertTo-Json -Compress)"
    }
    return $true
}
