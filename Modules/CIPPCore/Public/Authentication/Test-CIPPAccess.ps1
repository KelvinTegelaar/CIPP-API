function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList
    )

    if (!$Request.Headers.'x-ms-client-principal') {
        # Direct API Access
        $CustomRoles = @('CIPP-API')
    } else {
        $DefaultRoles = @('admin', 'editor', 'readonly', 'anonymous', 'authenticated')
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json
        if ($User.userRoles -contains 'admin' -or $User.userRoles -contains 'superadmin') {
            if ($TenantList.IsPresent) {
                return @('AllTenants')
            }
            return $true
        }

        $CustomRoles = $User.userRoles | ForEach-Object {
            if ($DefaultRoles -notcontains $_) {
                $_
            }
        }
    }
    if (($CustomRoles | Measure-Object).Count -gt 0) {
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
                    if (($Permission.AllowedTenants | Measure-Object).Count -eq 0 -and ($Permission.BlockedTenants | Measure-Object).Count -eq 0) {
                        return @('AllTenants')
                    } else {
                        if ($Permission.AllowedTenants -contains 'AllTenants') {
                            $Permission.AllowedTenants = $Tenants.customerId
                        }
                        $Permission.AllowedTenants | Where-Object { $Permission.BlockedTenants -notcontains $_ }
                    }
                }
                Write-Information ($LimitedTenantList | ConvertTo-Json)
                return $LimitedTenantList
            }

            if (($PermissionSet | Measure-Object).Count -eq 0) {
                return $true
            } else {
                $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint
                $Help = Get-Help $FunctionName
                # Check API for required role
                $APIRole = $Help.Role
                foreach ($Role in $PermissionSet) {
                    # Loop through each custom role permission and check API / Tenant access
                    $TenantAllowed = $false
                    $APIAllowed = $false
                    foreach ($Perm in $Role.Permissions) {
                        if ($Perm -match $APIRole) {
                            $APIAllowed = $true
                            break
                        }
                    }
                    if ($APIAllowed) {
                        # Check tenant level access
                        if (($Role.BlockedTenants | Measure-Object).Count -eq 0 -and $Role.AllowedTenants -contains 'AllTenants') {
                            $TenantAllowed = $true
                        } elseif ($Request.Query.TenantFilter -eq 'AllTenants' -or $Request.Body.TenantFilter -eq 'AllTenants') {
                            $TenantAllowed = $false
                        } else {
                            $Tenant = ($Tenants | Where-Object { $Request.Query.TenantFilter -eq $_.customerId -or $Request.Body.TenantFilter -eq $_.customerId -or $Request.Query.TenantFilter -eq $_.defaultDomainName -or $Request.Body.TenantFilter -eq $_.defaultDomainName }).customerId
                            if ($Role.AllowedTenants -contains 'AllTenants') {
                                $AllowedTenants = $Tenants
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
                    throw "Access to this CIPP API endpoint is not allowed, the '$($Role.Role)' custom role does not have the required permission: $APIRole"
                }
                if (!$TenantAllowed) {
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
    } else {
        return $true
    }
}