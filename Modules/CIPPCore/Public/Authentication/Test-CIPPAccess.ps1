function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList,
        [switch]$GroupList
    )
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
            Write-Debug "Loaded function permission data from cache for '$FunctionName': Role='$APIRole', Functionality='$Functionality'"
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

                if (($ScopeRules | Measure-Object).Count -eq 0) {
                    # No role produced a scope, so the caller is entitled to nothing
                    return @()
                }

                if ($TenantList.IsPresent) {
                    $swTenantList = [System.Diagnostics.Stopwatch]::StartNew()
                    $NeedsTenantList = @($ScopeRules | Where-Object { -not $_.Unrestricted -and $_.AllowAllTenants }).Count -gt 0
                    $Tenants = if ($NeedsTenantList) { Get-Tenants -IncludeErrors } else { @() }

                    $LimitedTenantList = foreach ($Rule in $ScopeRules) {
                        if ($Rule.Unrestricted) {
                            @('AllTenants')
                        } else {
                            $AllowedForRule = if ($Rule.AllowAllTenants) { $Tenants.customerId } else { $Rule.AllowedTenants }
                            $AllowedForRule | Where-Object { $Rule.BlockedTenants -notcontains $_ }
                        }
                    }
                    $swTenantList.Stop()
                    $AccessTimings['BuildTenantList'] = $swTenantList.Elapsed.TotalMilliseconds
                    return @($LimitedTenantList | Sort-Object -Unique)
                }

                Write-Information "Getting allowed groups for roles: $($CustomRoles -join ', ')"
                $swGroupList = [System.Diagnostics.Stopwatch]::StartNew()
                $LimitedGroupList = foreach ($Rule in $ScopeRules) {
                    if ($Rule.Unrestricted) { @('AllGroups') } else { $Rule.AllowedGroups }
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
                # Resolve the target from the request only. Do not fall back to $env:TenantID —
                # that is the partner/home tenant, not a customer. A missing filter means the
                # endpoint is not tenant-scoped; a filter that resolves to no known tenant is
                # denied on the allow pass and stays in scope for the block pass.
                $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter ?? $Request.Query.tenantId ?? $Request.Body.tenantId.value ?? $Request.Body.tenantId
                $TenantAllowed = $false
                $APIAllowed = $false
                $swPermissionEval = [System.Diagnostics.Stopwatch]::StartNew()

                # Block pass: deny wins, but only when the blocking role also grants the
                # permission and its tenant scope covers the target. -TreatUnresolvedAsInScope
                # keeps unresolved targets in scope so the deny still applies (fail closed).
                foreach ($Role in $PermissionSet) {
                    $RoleGrantsPermission = $false
                    foreach ($Perm in $Role.Permissions) {
                        if ($Perm -match $APIRole) {
                            $RoleGrantsPermission = $true
                            break
                        }
                    }
                    if (-not $RoleGrantsPermission) { continue }
                    if ($Role.BlockedEndpoints -notcontains $Request.Params.CIPPEndpoint) { continue }

                    $BlockInScope = Test-CippRoleTenantScope -Role $Role -TenantFilter $TenantFilter -Tenants $Tenants -Request $Request -ApiRole $APIRole -TreatUnresolvedAsInScope
                    if ($BlockInScope) {
                        throw "Access to this CIPP API endpoint is not allowed, the custom role '$($Role.Role)' has blocked this endpoint: $($Request.Params.CIPPEndpoint)"
                    }
                }

                # Allow pass: sticky $APIAllowed preserved (permission from one role + tenant
                # from another can still succeed). BlockedEndpoints already handled above.
                foreach ($Role in $PermissionSet) {
                    foreach ($Perm in $Role.Permissions) {
                        if ($Perm -match $APIRole) {
                            $APIAllowed = $true
                            break
                        }
                    }

                    if ($APIAllowed) {
                        $TenantAllowed = Test-CippRoleTenantScope -Role $Role -TenantFilter $TenantFilter -Tenants $Tenants -Request $Request -ApiRole $APIRole
                        if (!$TenantAllowed) { continue }
                        break
                    }
                }
                $swPermissionEval.Stop()
                $AccessTimings['EvaluatePermissions'] = $swPermissionEval.Elapsed.TotalMilliseconds

                if (!$APIAllowed) {
                    throw "Access to this CIPP API endpoint is not allowed, you do not have the required permission: $APIRole"
                }
                if (!$TenantAllowed -and $Functionality -notmatch 'AnyTenant') {
                    throw 'Access to this tenant is not allowed'
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
        $AccessTimingsRounded = [ordered]@{}
        foreach ($Key in ($AccessTimings.Keys | Sort-Object)) { $AccessTimingsRounded[$Key] = [math]::Round($AccessTimings[$Key], 2) }
        Write-Debug "#### Access Timings #### $($AccessTimingsRounded | ConvertTo-Json -Compress)"
        return @('AllTenants')
    }
    $AccessTotalSw.Stop()
    $AccessTimings['Total'] = $AccessTotalSw.Elapsed.TotalMilliseconds
    $AccessTimingsRounded = [ordered]@{}
    foreach ($Key in ($AccessTimings.Keys | Sort-Object)) { $AccessTimingsRounded[$Key] = [math]::Round($AccessTimings[$Key], 2) }
    Write-Debug "#### Access Timings #### $($AccessTimingsRounded | ConvertTo-Json -Compress)"
    return $true
}
