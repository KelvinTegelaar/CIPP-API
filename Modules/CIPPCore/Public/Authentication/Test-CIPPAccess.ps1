function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList
    )
    if ($Request.Params.CIPPEndpoint -eq 'ExecSAMSetup') { return $true }

    # Get function help
    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint
    $Help = Get-Help $FunctionName

    # Check help for role
    $APIRole = $Help.Role

    if ($APIRole -eq 'Public') {
        return $true
    }

    # Get default roles from config
    $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
    $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
    $BaseRoles = Get-Content -Path $CIPPRoot\Config\cipp-roles.json | ConvertFrom-Json

    if ($Request.Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Request.Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
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
                    $CustomRoles = @($Client.Role)
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
        $DefaultRoles = @('admin', 'editor', 'readonly', 'anonymous', 'authenticated')
        $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json

        if (!$TenantList.IsPresent -and $APIRole -match 'SuperAdmin' -and $User.userRoles -notcontains 'superadmin') {
            throw 'Access to this CIPP API endpoint is not allowed, the user does not have the required permission'
        }

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

            if (!$APIAllowed) {
                throw "Access to this CIPP API endpoint is not allowed, you do not have the required permission: $APIRole"
            }
            if (!$TenantAllowed -and $Help.Functionality -notmatch 'AnyTenant') {
                Write-Information "Tenant not allowed: $TenantFilter"
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
        }
    } else {
        return $true
    }
}
