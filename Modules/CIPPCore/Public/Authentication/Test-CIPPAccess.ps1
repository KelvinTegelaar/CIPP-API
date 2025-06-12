function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList
    )
    if ($Request.Params.CIPPEndpoint -eq 'ExecSAMSetup') { return $true }

    # Get function help
    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint

    try {
        $Help = Get-Help $FunctionName -ErrorAction Stop
    } catch {}

    # Check help for role
    $APIRole = $Help.Role

    if ($APIRole -eq 'Public') {
        return $true
    }

    # Get default roles from config
    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $BaseRoles = Get-Content -Path $CIPPRoot\Config\cipp-roles.json | ConvertFrom-Json

    if ($APIRole -eq 'Public') {
        return $true
    }

    # Get default roles from config
    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $BaseRoles = Get-Content -Path $CIPPRoot\Config\cipp-roles.json | ConvertFrom-Json
    $DefaultRoles = @('superadmin', 'admin', 'editor', 'readonly', 'anonymous', 'authenticated')

    if ($APIRole -eq 'Public') {
        return $true
    }

    # Get default roles from config
    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $BaseRoles = Get-Content -Path $CIPPRoot\Config\cipp-roles.json | ConvertFrom-Json

    if ($Request.Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Request.Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        $Type = 'APIClient'
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
    } else {
        $Type = 'User'
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

        # Check for roles granted via group membership
        if (($User.userRoles | Measure-Object).Count -eq 2 -and $User.userRoles -contains 'authenticated' -and $User.userRoles -contains 'anonymous') {
            $User = Test-CIPPAccessUserRole -User $User
        }

        #Write-Information ($User | ConvertTo-Json -Depth 5)
        # Return user permissions
        if ($Request.Params.CIPPEndpoint -eq 'me') {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = (@{ 'clientPrincipal' = $User } | ConvertTo-Json -Depth 5)
                })
            return
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
            $Tenants = Get-Tenants -IncludeErrors
            $PermissionsFound = $false
            $PermissionSet = foreach ($CustomRole in $CustomRoles) {
                try {
                    Get-CIPPRolePermissions -Role $CustomRole
                    $PermissionsFound = $true
                } catch {
                    Write-Information $_.Exception.Message
                    continue
                }
            }
            if ($PermissionsFound) {
                if ($TenantList.IsPresent) {
                    $LimitedTenantList = foreach ($Permission in $PermissionSet) {
                        if ((($Permission.AllowedTenants | Measure-Object).Count -eq 0 -or $Permission.AllowedTenants -contains 'AllTenants') -and (($Permission.BlockedTenants | Measure-Object).Count -eq 0)) {
                            @('AllTenants')
                        } else {
                            if ($Permission.AllowedTenants -contains 'AllTenants') {
                                $Permission.AllowedTenants = $Tenants.customerId
                            }
                            $Permission.AllowedTenants | Where-Object { $Permission.BlockedTenants -notcontains $_ }
                        }
                    }
                    return $LimitedTenantList
                }

                $TenantAllowed = $false
                $APIAllowed = $false
                foreach ($Role in $PermissionSet) {
                    foreach ($Perm in $Role.Permissions) {
                        if ($Perm -match $APIRole) {
                            $APIAllowed = $true
                            break
                        }
                    }

                    if ($APIAllowed) {
                        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter ?? $Request.Body.tenantFilter.value ?? $Request.Query.tenantId ?? $Request.Body.tenantId ?? $Request.Body.tenantId.value ?? $env:TenantID
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

                if (!$APIAllowed) {
                    throw "Access to this CIPP API endpoint is not allowed, you do not have the required permission: $APIRole"
                }
                if (!$TenantAllowed -and $Help.Functionality -notmatch 'AnyTenant') {
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
                    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter ?? $Request.Query.tenantId ?? $Request.Body.tenantId ?? $env:TenantID
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

            if (!$TenantAllowed -and $Help.Functionality -notmatch 'AnyTenant') {

                if (!$APIAllowed) {
                    throw "Access to this CIPP API endpoint is not allowed, you do not have the required permission: $APIRole"
                }
                if (!$TenantAllowed -and $Help.Functionality -notmatch 'AnyTenant') {
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
    }

    if ($TenantList.IsPresent) {
        return @('AllTenants')
    }
    return $true
}
