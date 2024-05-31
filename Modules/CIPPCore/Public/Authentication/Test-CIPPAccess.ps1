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
    if (($CustomRoles | Measure-Object).Count -gt 0 ) {
        $Tenants = Get-Tenants -IncludeErrors
        $PermissionSet = foreach ($CustomRole in $CustomRoles) {
            try {
                Get-CIPPRolePermissions -Role $CustomRole
            } catch {
                Write-Information $_.Exception.Message
            }
        }
        if ($TenantList.IsPresent) {
            $AllowedTenants = foreach ($Permission in $PermissionSet) {
                foreach ($Tenant in $Permission.AllowedTenants) {
                    $Tenant
                }
            }
            return $AllowedTenants
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
                    if ($Role.AllowedTenants -contains 'AllTenants') {
                        $TenantAllowed = $true
                    } elseif ($Request.Query.TenantFilter -eq 'AllTenants' -or $Request.Body.TenantFilter -eq 'AllTenants') {
                        $TenantAllowed = $false
                    } else {
                        $Tenant = ($Tenants | Where-Object { $Request.Query.TenantFilter -eq $_.customerId -or $Request.Body.TenantFilter -eq $_.customerId -or $Request.Query.TenantFilter -eq $_.defaultDomainName -or $Request.Body.TenantFilter -eq $_.defaultDomainName }).customerId

                        if ($Tenant) {
                            $TenantAllowed = $Role.AllowedTenants -contains $Tenant
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
        return $true
    }
}