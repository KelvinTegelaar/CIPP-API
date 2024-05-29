function Test-CIPPAccess {
    param(
        $Request,
        [switch]$TenantList
    )
    $DefaultRoles = @('admin', 'editor', 'readonly', 'anonymous', 'authenticated')
    $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json
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
    if (($CustomRoles | Measure-Object).Count -gt 0 ) {
        $Tenants = Get-Tenants -IncludeErrors
        $APIAllowed = $false
        $TenantAllowed = $false
        $PermissionSet = foreach ($CustomRole in $CustomRoles) {
            Get-CIPPRolePermissions -Role $CustomRole
        }
        if ($TenantList.IsPresent) {
            $AllowedTenants = foreach ($Permission in $PermissionSet) {
                foreach ($Tenant in $Permission.AllowedTenants) {
                    $Tenant
                }
            }
            return $AllowedTenants
        }
        $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint
        $Help = Get-Help $FunctionName
        $APIRole = $Help.Role
        foreach ($Role in $PermissionSet) {
            foreach ($Perm in $Role.Permissions) {
                if ($Perm -match $APIRole) {
                    $APIAllowed = $true
                    break
                }
            }
            if ($APIAllowed) {
                if ($Role.AllowedTenants -contains 'AllTenants') {
                    $TenantAllowed = $true
                } elseif ($Request.Query.TenantFilter -eq 'AllTenants' -or $Request.Body.TenantFilter -eq 'AllTenants') {
                    $TenantAllowed = $false
                } else {
                    $Tenant = ($Tenants | Where-Object { $Request.Query.TenantFilter -eq $_.customerId -or $Request.Body.TenantFilter -eq $_.customerId -or $Request.Query.TenantFilter -eq $_.defaultDomainName -or $Request.Body.TenantFilter -eq $_.defaultDomainName }).customerId

                    if ($Tenant) {
                        $TenantAllowed = $Role.AllowedTenants -contains $Tenant
                    } else {
                        $TenantAllowed = $true
                    }
                }
                if ($TenantAllowed) {
                    return $true
                } else {
                    throw 'Access to this tenant is not allowed'
                }
            }
        }
        if (!$APIAllowed) {
            throw "Access to this API is not allowed, required permission missing: $APIRole"
        }
    } else {
        return $true
    }
}