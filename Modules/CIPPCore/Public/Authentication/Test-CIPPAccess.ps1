function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList,
        [switch]$GroupList
    )
    # Initialize per-call profiling
    $AccessTimings = @{}
    $AccessTotalSw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($Request.Params.CIPPEndpoint -eq 'ExecSAMSetup') { return $true }

    # Get function help
    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint

    $SwPermissions = [System.Diagnostics.Stopwatch]::StartNew()
    if (-not $global:CIPPFunctionPermissions) {
        $CIPPCoreModule = Get-Module -Name CIPPCore
        if ($CIPPCoreModule) {
            $PermissionsFileJson = Join-Path $CIPPCoreModule.ModuleBase 'lib' 'data' 'function-permissions.json'

            if (Test-Path $PermissionsFileJson) {
                try {
                    $jsonData = Get-Content -Path $PermissionsFileJson -Raw | ConvertFrom-Json -AsHashtable
                    $global:CIPPFunctionPermissions = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
                    foreach ($key in $jsonData.Keys) {
                        $global:CIPPFunctionPermissions[$key] = $jsonData[$key]
                    }
                    Write-Debug "Loaded $($global:CIPPFunctionPermissions.Count) function permissions from JSON cache"
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
        if ($global:CIPPFunctionPermissions -and $global:CIPPFunctionPermissions.ContainsKey($FunctionName)) {
            $PermissionData = $global:CIPPFunctionPermissions[$FunctionName]
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

    # Get default roles from config
    $swRolesLoad = [System.Diagnostics.Stopwatch]::StartNew()
    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $BaseRoles = Get-Content -Path $CIPPRoot\Config\cipp-roles.json | ConvertFrom-Json
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
        $ForwardedFor = $Request.Headers.'x-forwarded-for' -split ',' | Select-Object -First 1
        $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $IPAddress = $ForwardedFor -replace $IPRegex, '$1' -replace '[\[\]]', ''

        $Client = Get-CippApiClient -AppId $Request.Headers.'x-ms-client-principal-name'
        if ($Client) {
            Write-Information "API Access: AppName=$($Client.AppName), AppId=$($Request.Headers.'x-ms-client-principal-name'), IP=$IPAddress"
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
                    $BaseRole = $null
                    foreach ($Role in $BaseRoles.PSObject.Properties) {
                        foreach ($ClientRole in $Client.Role) {
                            if ($Role.Name -eq $ClientRole) {
                                $BaseRole = $Role
                                break
                            }
                        }
                    }
                } else {
                    $CustomRoles = @('cipp-api')
                }
            } else {
                throw 'Access to this CIPP API endpoint is not allowed, the API Client does not have the required permission'
            }
        } else {
            $CustomRoles = @('cipp-api')
            Write-Information "API Access: AppId=$($Request.Headers.'x-ms-client-principal-name'), IP=$IPAddress"
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
                            'permissions'     = $Permissions
                        } | ConvertTo-Json -Depth 5)
                })
        }
        $swApiClient.Stop()
        $AccessTimings['ApiClientBranch'] = $swApiClient.Elapsed.TotalMilliseconds

    } else {
        $Type = 'User'
        $swUserBranch = [System.Diagnostics.Stopwatch]::StartNew()
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

        # Check for roles granted via group membership
        if (($User.userRoles | Measure-Object).Count -eq 2 -and $User.userRoles -contains 'authenticated' -and $User.userRoles -contains 'anonymous') {
            $swResolveUserRoles = [System.Diagnostics.Stopwatch]::StartNew()
            $User = Test-CIPPAccessUserRole -User $User
            $swResolveUserRoles.Stop()
            $AccessTimings['ResolveUserRoles'] = $swResolveUserRoles.Elapsed.TotalMilliseconds
        }

        $swIPCheck = [System.Diagnostics.Stopwatch]::StartNew()
        $AllowedIPRanges = Get-CIPPRoleIPRanges -Roles $User.userRoles

        if ($AllowedIPRanges -notcontains 'Any') {
            $ForwardedFor = $Request.Headers.'x-forwarded-for' -split ',' | Select-Object -First 1
            $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
            $IPAddress = $ForwardedFor -replace $IPRegex, '$1' -replace '[\[\]]', ''
            if ($IPAddress) {
                $IPAllowed = $false
                foreach ($Range in $AllowedIPRanges) {
                    if ($IPAddress -eq $Range -or (Test-IpInRange -IPAddress $IPAddress -Range $Range)) {
                        $IPAllowed = $true
                        break
                    }
                }

                if (-not $IPAllowed -and -not $Request.Params.CIPPEndpoint -eq 'me') {
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

        if ($Request.Params.CIPPEndpoint -eq 'me') {

            if (!$User.userRoles) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = (
                            @{
                                'clientPrincipal' = $null
                                'permissions'     = @()
                            } | ConvertTo-Json -Depth 5)
                    })
            }

            if (!$IPAllowed) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = (
                            @{
                                'clientPrincipal' = $null
                                'permissions'     = @()
                                'message'         = "Your IP address ($IPAddress) is not in the allowed range for your role(s)"
                            } | ConvertTo-Json -Depth 5)
                    })
            }

            $swPermsMe = [System.Diagnostics.Stopwatch]::StartNew()
            $Permissions = Get-CippAllowedPermissions -UserRoles $User.userRoles
            $swPermsMe.Stop()
            $AccessTimings['GetPermissions(me)'] = $swPermsMe.Elapsed.TotalMilliseconds
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = (
                        @{
                            'clientPrincipal' = $User
                            'permissions'     = $Permissions
                        } | ConvertTo-Json -Depth 5)
                })
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
        foreach ($Role in $BaseRoles.PSObject.Properties) {
            foreach ($UserRole in $User.userRoles) {
                if ($Role.Name -eq $UserRole) {
                    $BaseRole = $Role
                    break
                }
            }
        }

    }

    # Check base role permissions before continuing to custom roles
    if ($null -ne $BaseRole) {
        Write-Information "Base Role: $($BaseRole.Name)"
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
        Write-Information $BaseRole.Name
        throw 'Access to this CIPP API endpoint is not allowed, the user does not have the required permission'
    } elseif (($CustomRoles | Measure-Object).Count -gt 0) {
        if (@('admin', 'superadmin') -contains $BaseRole.Name) {
            return $true
        } else {
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
                    continue
                }
            }
            $swRolePerms.Stop()
            $AccessTimings['GetRolePermissions'] = $swRolePerms.Elapsed.TotalMilliseconds

            if ($PermissionsFound) {
                if ($TenantList.IsPresent) {
                    $swTenantList = [System.Diagnostics.Stopwatch]::StartNew()
                    $LimitedTenantList = foreach ($Permission in $PermissionSet) {
                        if ((($Permission.AllowedTenants | Measure-Object).Count -eq 0 -or $Permission.AllowedTenants -contains 'AllTenants') -and (($Permission.BlockedTenants | Measure-Object).Count -eq 0)) {
                            @('AllTenants')
                        } else {
                            # Expand tenant groups to individual tenant IDs
                            $ExpandedAllowedTenants = foreach ($AllowedItem in $Permission.AllowedTenants) {
                                if ($AllowedItem -is [PSCustomObject] -and $AllowedItem.type -eq 'Group') {
                                    try {
                                        $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($AllowedItem)
                                        $GroupMembers | ForEach-Object { $_.addedFields.customerId }
                                    } catch {
                                        Write-Warning "Failed to expand tenant group '$($AllowedItem.label)': $($_.Exception.Message)"
                                        @()
                                    }
                                } else {
                                    $AllowedItem
                                }
                            }

                            $ExpandedBlockedTenants = foreach ($BlockedItem in $Permission.BlockedTenants) {
                                if ($BlockedItem -is [PSCustomObject] -and $BlockedItem.type -eq 'Group') {
                                    try {
                                        $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($BlockedItem)
                                        $GroupMembers | ForEach-Object { $_.addedFields.customerId }
                                    } catch {
                                        Write-Warning "Failed to expand blocked tenant group '$($BlockedItem.label)': $($_.Exception.Message)"
                                        @()
                                    }
                                } else {
                                    $BlockedItem
                                }
                            }

                            if ($ExpandedAllowedTenants -contains 'AllTenants') {
                                $ExpandedAllowedTenants = $Tenants.customerId
                            }
                            $ExpandedAllowedTenants | Where-Object { $ExpandedBlockedTenants -notcontains $_ }
                        }
                    }
                    $swTenantList.Stop()
                    $AccessTimings['BuildTenantList'] = $swTenantList.Elapsed.TotalMilliseconds
                    return @($LimitedTenantList | Sort-Object -Unique)
                } elseif ($GroupList.IsPresent) {
                    $swGroupList = [System.Diagnostics.Stopwatch]::StartNew()
                    Write-Information "Getting allowed groups for roles: $($CustomRoles -join ', ')"
                    $LimitedGroupList = foreach ($Permission in $PermissionSet) {
                        if ((($Permission.AllowedTenants | Measure-Object).Count -eq 0 -or $Permission.AllowedTenants -contains 'AllTenants') -and (($Permission.BlockedTenants | Measure-Object).Count -eq 0)) {
                            @('AllGroups')
                        } else {
                            foreach ($AllowedItem in $Permission.AllowedTenants) {
                                if ($AllowedItem -is [PSCustomObject] -and $AllowedItem.type -eq 'Group') {
                                    $AllowedItem.value
                                }
                            }
                        }
                    }
                    $swGroupList.Stop()
                    $AccessTimings['BuildGroupList'] = $swGroupList.Elapsed.TotalMilliseconds
                    return @($LimitedGroupList | Sort-Object -Unique)
                }

                $TenantAllowed = $false
                $APIAllowed = $false
                $swPermissionEval = [System.Diagnostics.Stopwatch]::StartNew()
                foreach ($Role in $PermissionSet) {
                    foreach ($Perm in $Role.Permissions) {
                        if ($Perm -match $APIRole) {
                            if ($Role.BlockedEndpoints -contains $Request.Params.CIPPEndpoint) {
                                throw "Access to this CIPP API endpoint is not allowed, the custom role '$($Role.Role)' has blocked this endpoint: $($Request.Params.CIPPEndpoint)"
                            }
                            $APIAllowed = $true
                            break
                        }
                    }

                    if ($APIAllowed) {
                        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter ?? $Request.Query.tenantId ?? $Request.Body.tenantId.value ?? $Request.Body.tenantId ?? $env:TenantID
                        # Check tenant level access
                        if (($Role.BlockedTenants | Measure-Object).Count -eq 0 -and $Role.AllowedTenants -contains 'AllTenants') {
                            $TenantAllowed = $true
                        } elseif ($TenantFilter -eq 'AllTenants' -and $ApiRole -match 'Write$') {
                            $TenantAllowed = $false
                        } elseif ($TenantFilter -eq 'AllTenants' -and $ApiRole -match 'Read$') {
                            $TenantAllowed = $true
                        } else {
                            $Tenant = ($Tenants | Where-Object { $TenantFilter -eq $_.customerId -or $TenantFilter -eq $_.defaultDomainName }).customerId

                            # Expand allowed tenant groups to individual tenant IDs
                            $ExpandedAllowedTenants = foreach ($AllowedItem in $Role.AllowedTenants) {
                                if ($AllowedItem -is [PSCustomObject] -and $AllowedItem.type -eq 'Group') {
                                    try {
                                        $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($AllowedItem)
                                        $GroupMembers | ForEach-Object { $_.addedFields.customerId }
                                    } catch {
                                        Write-Warning "Failed to expand allowed tenant group '$($AllowedItem.label)': $($_.Exception.Message)"
                                        @()
                                    }
                                } else {
                                    $AllowedItem
                                }
                            }

                            # Expand blocked tenant groups to individual tenant IDs
                            $ExpandedBlockedTenants = foreach ($BlockedItem in $Role.BlockedTenants) {
                                if ($BlockedItem -is [PSCustomObject] -and $BlockedItem.type -eq 'Group') {
                                    try {
                                        $GroupMembers = Expand-CIPPTenantGroups -TenantFilter @($BlockedItem)
                                        $GroupMembers | ForEach-Object { $_.addedFields.customerId }
                                    } catch {
                                        Write-Warning "Failed to expand blocked tenant group '$($BlockedItem.label)': $($_.Exception.Message)"
                                        @()
                                    }
                                } else {
                                    $BlockedItem
                                }
                            }

                            if ($ExpandedAllowedTenants -contains 'AllTenants') {
                                $AllowedTenants = $Tenants.customerId
                            } else {
                                $AllowedTenants = $ExpandedAllowedTenants
                            }

                            if ($Tenant) {
                                $TenantAllowed = $AllowedTenants -contains $Tenant -and $ExpandedBlockedTenants -notcontains $Tenant
                                if (!$TenantAllowed) { continue }
                                break
                            } else {
                                $TenantAllowed = $true
                                break
                            }
                        }
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
                    return @('AllTenants')
                }
                return $true
                if ($APIAllowed) {
                    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter ?? $Request.Query.tenantId ?? $Request.Body.tenantId.value ?? $Request.Body.tenantId ?? $env:TenantID
                    # Check tenant level access
                    if (($Role.BlockedTenants | Measure-Object).Count -eq 0 -and $Role.AllowedTenants -contains 'AllTenants') {
                        $TenantAllowed = $true
                    } elseif ($TenantFilter -eq 'AllTenants') {
                        $TenantAllowed = $false
                    } else {
                        $Tenant = ($Tenants | Where-Object { $TenantFilter -eq $_.customerId -or $TenantFilter -eq $_.defaultDomainName }).customerId

                        if ($Role.AllowedTenants -contains 'AllTenants') {
                            $AllowedTenants = $Tenants.customerId
                        } else {
                            $AllowedTenants = $Role.AllowedTenants
                        }
                        if ($Tenant) {
                            $TenantAllowed = $AllowedTenants -contains $Tenant -and $Role.BlockedTenants -notcontains $Tenant
                            if (!$TenantAllowed) { continue }
                            break
                        } else {
                            $TenantAllowed = $true
                            break
                        }
                    }
                }
            }

            if (!$TenantAllowed -and $Functionality -notmatch 'AnyTenant') {

                if (!$APIAllowed) {
                    throw "Access to this CIPP API endpoint is not allowed, you do not have the required permission: $APIRole"
                }
                if (!$TenantAllowed -and $Functionality -notmatch 'AnyTenant') {
                    Write-Information "Tenant not allowed: $TenantFilter"

                    throw 'Access to this tenant is not allowed'
                } else {
                    return $true
                }

            }
        } else {
            # No permissions found for any roles
            if ($TenantList.IsPresent) {
                return @('AllTenants')
            }
            return $true
        }
        $swUserBranch.Stop()
        $AccessTimings['UserBranch'] = $swUserBranch.Elapsed.TotalMilliseconds
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
