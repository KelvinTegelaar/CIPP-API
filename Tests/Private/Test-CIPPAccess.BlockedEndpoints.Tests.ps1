# Regression tests for tenant-scoped BlockedEndpoints in Test-CIPPAccess.
#
# BlockedEndpoints used to throw before tenant resolution, so a role scoped to T1 that blocked an
# endpoint also blocked that endpoint on T2. Deny still wins, but only when the blocking role's
# tenant scope covers the request target.
#
# Driven through the APIClient path (aad idp + GUID principal name).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication'
    $FunctionPath = Join-Path $AuthDir 'Test-CIPPAccess.ps1'
    $ScopeHelperPath = Join-Path $AuthDir 'Test-CippRoleTenantScope.ps1'

    function Get-CippApiClient { param($AppId) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Get-CIPPRolePermissions { param($Role) }
    function Get-Tenants { param([switch]$IncludeErrors) @() }
    function Get-CippAccessScopeRule { param($Role) }
    function Expand-CIPPTenantGroups { param($TenantFilter) @() }

    . $ScopeHelperPath
    . $FunctionPath

    $script:CIPPFunctionPermissions = @{
        'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' }
    }
    $script:CIPPBaseRoles = [pscustomobject]@{}

    $script:Tenant1 = [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com' }
    $script:Tenant2 = [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 't2.example.com' }

    function New-EndpointRequest {
        param(
            [string]$TenantId,
            [object]$TenantFilterBody
        )
        $Body = if ($PSBoundParameters.ContainsKey('TenantFilterBody')) {
            @{ tenantFilter = $TenantFilterBody }
        } elseif ($TenantId) {
            @{ tenantFilter = $TenantId }
        } else {
            @{}
        }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecResetPass' }
            Headers = @{
                'x-ms-client-principal-idp'  = 'aad'
                'x-ms-client-principal-name' = '11111111-1111-1111-1111-111111111111'
                'x-forwarded-for'            = '1.2.3.4'
            }
            Query   = @{}
            Body    = $Body
        }
    }

    function New-RoleObject {
        param(
            [string]$Name,
            [string[]]$Permissions = @('Identity.User.ReadWrite'),
            [object[]]$AllowedTenants = @('AllTenants'),
            [object[]]$BlockedTenants = @(),
            [string[]]$BlockedEndpoints = @()
        )
        [pscustomobject]@{
            Role             = $Name
            Permissions      = $Permissions
            AllowedTenants   = $AllowedTenants
            BlockedTenants   = $BlockedTenants
            BlockedEndpoints = $BlockedEndpoints
        }
    }
}

Describe 'Test-CIPPAccess BlockedEndpoints tenant scoping' {
    BeforeEach {
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
    }

    It 'blocks when AllTenants role lists the endpoint' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('allrole'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 'allrole' -BlockedEndpoints @('ExecResetPass')
        }

        { Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-1') } |
            Should -Throw -ExpectedMessage '*has blocked this endpoint: ExecResetPass*'
    }

    It 'blocks when scoped role covers the request tenant' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('t1role'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 't1role' -AllowedTenants @('tenant-1') -BlockedEndpoints @('ExecResetPass')
        }

        { Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-1') } |
            Should -Throw -ExpectedMessage '*has blocked this endpoint: ExecResetPass*'
    }

    It 'allows T2 when RoleA blocks on T1 and RoleB grants T2 without a block' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('roleA', 'roleB'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            param($Role)
            switch ($Role) {
                'roleA' {
                    New-RoleObject -Name 'roleA' -AllowedTenants @('tenant-1') -BlockedEndpoints @('ExecResetPass')
                }
                'roleB' {
                    New-RoleObject -Name 'roleB' -AllowedTenants @('tenant-2') -BlockedEndpoints @()
                }
                default { throw "Unexpected role $Role" }
            }
        }

        $result = Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-2')
        $result | Should -BeTrue
    }

    It 'denies out-of-scope tenant with tenant message when only a blocking scoped role is held' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('t1role'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 't1role' -AllowedTenants @('tenant-1') -BlockedEndpoints @('ExecResetPass')
        }

        { Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-2') } |
            Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
    }

    It 'allows when role grants the endpoint with no block and tenant is in scope' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('t1role'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 't1role' -AllowedTenants @('tenant-1') -BlockedEndpoints @()
        }

        $result = Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-1')
        $result | Should -BeTrue
    }

    It 'fail-closes the block when tenantFilter does not map to a known tenant' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('t1role'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 't1role' -AllowedTenants @('tenant-1') -BlockedEndpoints @('ExecResetPass')
        }

        { Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-unknown') } |
            Should -Throw -ExpectedMessage '*has blocked this endpoint: ExecResetPass*'
    }

    It 'fail-closes the block when the request has no tenantFilter (does not invent partner TenantID)' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('t1role'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 't1role' -AllowedTenants @('tenant-1') -BlockedEndpoints @('ExecResetPass')
        }

        $env:TenantID = 'partner-tenant-id'
        { Test-CIPPAccess -Request (New-EndpointRequest) } |
            Should -Throw -ExpectedMessage '*has blocked this endpoint: ExecResetPass*'
    }

    It 'blocks a granted group-shaped tenantFilter when the endpoint is blocked' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('grouprole'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 'grouprole' `
                -AllowedTenants @([pscustomobject]@{ type = 'Group'; value = 'group-allowed'; label = 'Allowed Group' }) `
                -BlockedEndpoints @('ExecResetPass')
        }

        $GroupBody = [pscustomobject]@{ type = 'Group'; value = 'group-allowed'; label = 'Allowed Group' }
        { Test-CIPPAccess -Request (New-EndpointRequest -TenantFilterBody $GroupBody) } |
            Should -Throw -ExpectedMessage '*has blocked this endpoint: ExecResetPass*'
    }

    It 'does not apply the block for an ungranted group; allow path denies the group' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('grouprole'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 'grouprole' `
                -AllowedTenants @([pscustomobject]@{ type = 'Group'; value = 'group-allowed'; label = 'Allowed Group' }) `
                -BlockedEndpoints @('ExecResetPass')
        }

        $GroupBody = [pscustomobject]@{ type = 'Group'; value = 'group-notgranted'; label = 'Other Group' }
        { Test-CIPPAccess -Request (New-EndpointRequest -TenantFilterBody $GroupBody) } |
            Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
    }

    It 'does not block when the role lists BlockedEndpoints but does not grant the permission' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'TestApp'; Role = @('norole'); IPRange = @('Any') }
        }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            New-RoleObject -Name 'norole' `
                -Permissions @('Identity.User.Read') `
                -AllowedTenants @('AllTenants') `
                -BlockedEndpoints @('ExecResetPass')
        }

        { Test-CIPPAccess -Request (New-EndpointRequest -TenantId 'tenant-1') } |
            Should -Throw -ExpectedMessage '*required permission: Identity.User.ReadWrite*'
    }
}
