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

    if (!$Request.Headers.'x-ms-client-principal' -or ($Request.Headers.'x-ms-client-principal-id' -and $Request.Headers.'x-ms-client-principal-idp' -eq 'aad')) {
        # Direct API Access
        $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $IPAddress = $Request.Headers.'x-forwarded-for' -replace $IPRegex, '$1' -replace '[\[\]]', ''
        Write-Information "API Access: AppId=$($Request.Headers.'x-ms-client-principal-id') IP=$IPAddress"

        # TODO: Implement API Client support, create Get-CippApiClient function
        <#$Client = Get-CippApiClient -AppId $Request.Headers.'x-ms-client-principal-id'
        if ($Client) {
            if ($Client.AllowedIPs -contains $IPAddress -or $Client.AllowedIPs -contains 'All')) {
                if ($Client.CustomRoles) {
                    $CustomRoles = @($Client.CustomRoles)
                } else {
                    $CustomRoles = @('CIPP-API')
                }
            } else {
                throw 'Access to this CIPP API endpoint is not allowed, the API Client does not have the required permission'
            }
        } else { #>
        $CustomRoles = @('cipp-api')
        # }
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
                    if (($Permission.AllowedTenants | Measure-Object).Count -eq 0 -and ($Permission.BlockedTenants | Measure-Object).Count -eq 0) {
                        return @('AllTenants')
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
                    # Check tenant level access
                    if (($Role.BlockedTenants | Measure-Object).Count -eq 0 -and $Role.AllowedTenants -contains 'AllTenants') {
                        $TenantAllowed = $true
                    } elseif ($Request.Query.TenantFilter -eq 'AllTenants' -or $Request.Body.TenantFilter -eq 'AllTenants') {
                        $TenantAllowed = $false
                    } else {
                        $Tenant = ($Tenants | Where-Object { $Request.Query.TenantFilter -eq $_.customerId -or $Request.Body.TenantFilter -eq $_.customerId -or $Request.Query.TenantFilter -eq $_.defaultDomainName -or $Request.Body.TenantFilter -eq $_.defaultDomainName }).customerId
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
                throw "Access to this CIPP API endpoint is not allowed, the '$($Role.Role)' custom role does not have the required permission: $APIRole"
            }
            if (!$TenantAllowed) {
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