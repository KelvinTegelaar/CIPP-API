# Characterization tests for Test-CIPPAccess. These encode CURRENT behavior exactly,
# including quirks, so a later simplification pass is protected. The function is not changed.
#
# Harness mirrors the sibling Test-CIPPAccess.*.Tests.ps1 files: dot-source the function,
# stub the external surface, pre-seed the runspace caches ($script:CIPPFunctionPermissions,
# $script:CIPPBaseRoles) so no config/storage/network is touched.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication'
    $FunctionPath = Join-Path $AuthDir 'Test-CIPPAccess.ps1'
    $ScopeHelperPath = Join-Path $AuthDir 'Test-CippRoleTenantScope.ps1'

    # /me returns build [HttpResponseContext]@{...} with [HttpStatusCode]::OK; neither short
    # name resolves when the function is dot-sourced without `using namespace System.Net`,
    # so shim both. Only the /me IP-exemption test needs them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }
    enum HttpStatusCode {
        OK = 200
    }

    # Stub the full external surface every exercised path touches.
    function Get-CippApiClient { param($AppId) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Get-CIPPRolePermissions { param($Role) }
    function Get-Tenants { param([switch]$IncludeErrors) @() }
    function Get-CippAccessScopeRule { param($Role) }
    function Get-CIPPRoleIPRanges { param($Roles) @('Any') }
    function Test-CIPPAccessUserRole { param($User) $User }
    function Resolve-CippImpersonation { param($User, $Request) [pscustomobject]@{ User = $User; Impersonating = $null; RealRoles = $User.userRoles } }
    function Get-CippAllowedPermissions { param($UserRoles) @() }
    function Expand-CIPPTenantGroups { param($TenantFilter) @() }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $user, $LogData) }

    $PrivateAuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Private/Authentication'

    . $ScopeHelperPath
    . $FunctionPath
    . (Join-Path $PrivateAuthDir 'New-CippMeResponse.ps1')
    . (Join-Path $PrivateAuthDir 'Get-CippRequestIPAddress.ps1')
    . (Join-Path $PrivateAuthDir 'Find-CippBaseRole.ps1')

    # Base roles shaped like Config/cipp-roles.json (include/exclude wildcard arrays).
    $script:SeedBaseRoles = [pscustomobject]@{
        readonly   = [pscustomobject]@{ include = @('*.Read'); exclude = @('CIPP.SuperAdmin.*', 'CIPP.Admin.*', 'CIPP.AppSettings.*') }
        editor     = [pscustomobject]@{ include = @('*.Read', '*.ReadWrite'); exclude = @('CIPP.SuperAdmin.*', 'CIPP.Admin.*', 'CIPP.AppSettings.*', 'Tenant.Standards.ReadWrite') }
        admin      = [pscustomobject]@{ include = @('*'); exclude = @('CIPP.SuperAdmin.*') }
        superadmin = [pscustomobject]@{ include = @('*'); exclude = @() }
    }

    # Encode a user principal the way Azure SWA delivers it: base64(JSON) in x-ms-client-principal.
    function ConvertTo-PrincipalHeader {
        param($Principal)
        [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Principal | ConvertTo-Json -Depth 6 -Compress)))
    }

    # A user request. Pass an explicit principal object, or roles to build a standard one.
    function New-UserRequest {
        param(
            [string]$CIPPEndpoint = 'ExecResetPass',
            [string[]]$UserRoles = @('editor'),
            [object]$Principal,
            [hashtable]$Query = @{},
            [hashtable]$Body = @{},
            [string]$ForwardedFor = '1.2.3.4',
            [switch]$OmitForwardedFor
        )
        if (-not $PSBoundParameters.ContainsKey('Principal')) {
            $Principal = [pscustomobject]@{
                identityProvider = 'aad'
                userId           = '00000000-0000-0000-0000-000000000001'
                userDetails      = 'user@contoso.com'
                userRoles        = $UserRoles
            }
        }
        $Headers = @{
            'x-ms-client-principal'      = (ConvertTo-PrincipalHeader -Principal $Principal)
            'x-ms-client-principal-name' = 'user@contoso.com'
        }
        if (-not $OmitForwardedFor) { $Headers['x-forwarded-for'] = $ForwardedFor }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = $CIPPEndpoint }
            Headers = $Headers
            Query   = $Query
            Body    = $Body
        }
    }

    # An API-client request (aad idp + GUID principal name) -> APIClient branch.
    function New-ApiClientRequest {
        param(
            [string]$CIPPEndpoint = 'ExecResetPass',
            [hashtable]$Query = @{},
            [hashtable]$Body = @{},
            [string]$ForwardedFor = '1.2.3.4'
        )
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = $CIPPEndpoint }
            Headers = @{
                'x-ms-client-principal-idp'  = 'aad'
                'x-ms-client-principal-name' = '11111111-1111-1111-1111-111111111111'
                'x-forwarded-for'            = $ForwardedFor
            }
            Query   = $Query
            Body    = $Body
        }
    }
}

Describe 'Test-CIPPAccess Public role' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecPublicThing' = @{ Role = 'Public'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'returns $true immediately for a Public endpoint without touching identity' {
        # No principal header at all; Public must short-circuit before any identity processing.
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecPublicThing' }; Headers = @{}; Query = @{}; Body = @{} }
        Mock -CommandName Get-CippApiClient -MockWith { throw 'identity must not be processed for Public' }
        Test-CIPPAccess -Request $Request | Should -BeTrue
        Should -Invoke -CommandName Get-CippApiClient -Times 0
    }
}

Describe 'Test-CIPPAccess APIClient branch' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'unknown client (Get-CippApiClient returns null) gets the cipp-api custom role' {
        # Unknown client -> CustomRoles = @('cipp-api'); no base role; no scope rules -> required-permission throw.
        Mock -CommandName Get-CippApiClient -MockWith { $null }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith { throw 'no perms' }
        # cipp-api is not admin/superadmin, has no permissions found -> required-permission throw.
        { Test-CIPPAccess -Request (New-ApiClientRequest) } |
            Should -Throw -ExpectedMessage '*does not have the required permission*'
    }

    It 'known client with IPRange Any is allowed through the IP gate' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'App'; Role = @('somerole'); IPRange = @('Any') }
        }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            [pscustomobject]@{ Role = 'somerole'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('AllTenants'); BlockedTenants = @(); BlockedEndpoints = @() }
        }
        Test-CIPPAccess -Request (New-ApiClientRequest) | Should -BeTrue
    }

    It 'known client with a restrictive IPRange and an out-of-range IP throws the IP-permission error' {
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'App'; Role = @('somerole'); IPRange = @('10.0.0.0/24') }
        }
        Mock -CommandName Test-IpInRange -MockWith { $false }
        { Test-CIPPAccess -Request (New-ApiClientRequest -ForwardedFor '1.2.3.4') } |
            Should -Throw -ExpectedMessage '*the API Client does not have the required permission*'
    }

    It 'known client whose Role is a base role (admin) hits base include/exclude and falls through to $true' {
        # admin base role: include '*' matches APIRole, exclude 'CIPP.SuperAdmin.*' does not.
        # admin has no CustomRoles (admin is a default role) so base-role allow -> end-of-function $true.
        Mock -CommandName Get-CippApiClient -MockWith {
            [pscustomobject]@{ AppName = 'App'; Role = @('admin'); IPRange = @('Any') }
        }
        Test-CIPPAccess -Request (New-ApiClientRequest) | Should -BeTrue
    }
}

Describe 'Test-CIPPAccess User branch - identity and roles' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'rebuilds identity from claims when userDetails is blank and selects preferred_username + oid' {
        $Principal = [pscustomobject]@{
            userDetails = ''
            claims      = @(
                [pscustomobject]@{ typ = 'preferred_username'; val = 'claimed@contoso.com' }
                [pscustomobject]@{ typ = 'oid'; val = 'oid-from-claim' }
            )
        }
        # Rebuilt user gets userRoles @('authenticated','anonymous') -> Test-CIPPAccessUserRole is consulted.
        Mock -CommandName Test-CIPPAccessUserRole -MockWith {
            param($User)
            $User.userDetails | Should -Be 'claimed@contoso.com'
            $User.userId | Should -Be 'oid-from-claim'
            $User.userRoles = @('editor')
            $User
        }
        Test-CIPPAccess -Request (New-UserRequest -Principal $Principal) | Should -BeTrue
        Should -Invoke -CommandName Test-CIPPAccessUserRole -Times 1
    }

    It 'falls back to x-ms-client-principal-name when no UPN-type claim is present' {
        $Principal = [pscustomobject]@{
            userDetails = ''
            claims      = @([pscustomobject]@{ typ = 'oid'; val = 'oid-only' })
        }
        Mock -CommandName Test-CIPPAccessUserRole -MockWith {
            param($User)
            # No upn/preferred_username/email claim -> UPN falls back to the header name.
            $User.userDetails | Should -Be 'user@contoso.com'
            $User.userRoles = @('editor')
            $User
        }
        Test-CIPPAccess -Request (New-UserRequest -Principal $Principal) | Should -BeTrue
        Should -Invoke -CommandName Test-CIPPAccessUserRole -Times 1
    }

    It 'resolves roles via Test-CIPPAccessUserRole ONLY when userRoles is exactly authenticated+anonymous' {
        Mock -CommandName Test-CIPPAccessUserRole -MockWith { param($User) $User.userRoles = @('editor'); $User }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('authenticated', 'anonymous')) | Should -BeTrue
        Should -Invoke -CommandName Test-CIPPAccessUserRole -Times 1
    }

    It 'does NOT call Test-CIPPAccessUserRole when a concrete role is already present' {
        Mock -CommandName Test-CIPPAccessUserRole -MockWith { param($User) $User }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('editor')) | Should -BeTrue
        Should -Invoke -CommandName Test-CIPPAccessUserRole -Times 0
    }

    It 'throws unable-to-resolve-roles when no roles remain after resolution' {
        # authenticated+anonymous triggers resolution; resolver clears userRoles -> throw.
        Mock -CommandName Test-CIPPAccessUserRole -MockWith { param($User) $User.userRoles = @(); $User }
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('authenticated', 'anonymous')) } |
            Should -Throw -ExpectedMessage '*unable to resolve roles*'
    }
}

Describe 'Test-CIPPAccess User branch - IP enforcement' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{
            'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' }
            'Invoke-me'            = @{ Role = 'Public'; Functionality = 'Entrypoint' }
        }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'throws when the IP is outside the role allowed range' {
        Mock -CommandName Get-CIPPRoleIPRanges -MockWith { @('10.0.0.0/24') }
        Mock -CommandName Test-IpInRange -MockWith { $false }
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('editor') -ForwardedFor '1.2.3.4') } |
            Should -Throw -ExpectedMessage '*your IP address (1.2.3.4) is not in the allowed range*'
    }

    It 'does NOT throw on out-of-range IP for the /me endpoint (the /me exemption)' {
        # /me is exempt from the IP throw; it continues into the me-response build.
        # Env controls keep the me build off storage (CIPPNG=true skips the SSO table read).
        Mock -CommandName Get-CIPPRoleIPRanges -MockWith { @('10.0.0.0/24') }
        Mock -CommandName Test-IpInRange -MockWith { $false }
        Mock -CommandName Get-CippAllowedPermissions -MockWith { @() }
        $script:SavedNG = $env:CIPPNG
        $env:CIPPNG = 'true'
        try {
            $Result = Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'me' -UserRoles @('editor') -ForwardedFor '1.2.3.4')
            $Result.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        } finally {
            if ($null -eq $script:SavedNG) { Remove-Item Env:\CIPPNG -ErrorAction SilentlyContinue } else { $env:CIPPNG = $script:SavedNG }
        }
    }

    It 'allows when role IP ranges are Any' {
        Mock -CommandName Get-CIPPRoleIPRanges -MockWith { @('Any') }
        Mock -CommandName Test-IpInRange -MockWith { throw 'Test-IpInRange must not be called when range is Any' }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('editor')) | Should -BeTrue
        Should -Invoke -CommandName Test-IpInRange -Times 0
    }
}

Describe 'Test-CIPPAccess User branch - impersonation and AllTenants' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'downstream evaluation uses the impersonated users roles' {
        # Real user is superadmin; impersonation swaps to a restricted custom role with no permission -> throw.
        Mock -CommandName Resolve-CippImpersonation -MockWith {
            param($User, $Request)
            $Impersonated = [pscustomobject]@{ identityProvider = 'aad'; userId = 'x'; userDetails = 'target@contoso.com'; userRoles = @('restrictedrole') }
            [pscustomobject]@{ User = $Impersonated; Impersonating = 'target@contoso.com'; RealRoles = @('superadmin') }
        }
        Mock -CommandName Get-Tenants -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith { throw 'no perms for restrictedrole' }
        # If it had used the real superadmin role, admin/superadmin returns true early; instead restrictedrole
        # has no permissions -> required-permission throw, proving the impersonated role drove the decision.
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('superadmin')) } |
            Should -Throw -ExpectedMessage '*does not have the required permission*'
    }

    It 'admin + -TenantList returns @(AllTenants)' {
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('admin')) -TenantList | Should -Be @('AllTenants')
    }

    It 'superadmin + -TenantList returns @(AllTenants)' {
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('superadmin')) -TenantList | Should -Be @('AllTenants')
    }
}

Describe 'Test-CIPPAccess base role include/exclude' {
    BeforeAll {
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'allows when the base role include matches the APIRole' {
        # readonly.include '*.Read' matches 'Identity.User.Read'; readonly has no custom roles -> $true.
        $script:CIPPFunctionPermissions = @{ 'Invoke-ListUsers' = @{ Role = 'Identity.User.Read'; Functionality = 'Entrypoint' } }
        Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'ListUsers' -UserRoles @('readonly')) | Should -BeTrue
    }

    It 'throws the base-role error when an exclude matches even though an include also matched' {
        # readonly.include '*.Read' matches 'CIPP.AppSettings.Read', but exclude 'CIPP.AppSettings.*' wins.
        $script:CIPPFunctionPermissions = @{ 'Invoke-ListAppSettings' = @{ Role = 'CIPP.AppSettings.Read'; Functionality = 'Entrypoint' } }
        { Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'ListAppSettings' -UserRoles @('readonly')) } |
            Should -Throw -ExpectedMessage "*the 'readonly' base role does not have the required permission: CIPP.AppSettings.Read*"
    }

    It 'throws required-permission when there is no base role and zero custom roles' {
        # A role name that is neither a default nor a base role, but strip happens: user keeps the single
        # unknown role as a custom role. To hit the zero-custom-role path we need a default-only role set.
        # 'authenticated' alone (not the exact auth+anon pair) -> no resolution, no base role, no custom roles.
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('authenticated')) } |
            Should -Throw -ExpectedMessage '*the user does not have the required permission*'
    }
}

Describe 'Test-CIPPAccess -TenantList / -GroupList scope rules' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'returns @() when there are no scope rules at all' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith { throw 'no rule' }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -TenantList | Should -Be @()
    }

    It 'Unrestricted rule returns @(AllTenants) for -TenantList' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith { [pscustomobject]@{ Unrestricted = $true } }
        Mock -CommandName Get-Tenants -MockWith { throw 'Get-Tenants must not be called for Unrestricted' }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -TenantList | Should -Be @('AllTenants')
        Should -Invoke -CommandName Get-Tenants -Times 0
    }

    It 'Unrestricted rule returns @(AllGroups) for -GroupList' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith { [pscustomobject]@{ Unrestricted = $true } }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -GroupList | Should -Be @('AllGroups')
    }

    It 'AllowAllTenants (not unrestricted) calls Get-Tenants and excludes BlockedTenants' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith {
            [pscustomobject]@{ Unrestricted = $false; AllowAllTenants = $true; BlockedTenants = @('tenant-b'); AllowedTenants = @() }
        }
        Mock -CommandName Get-Tenants -MockWith {
            @([pscustomobject]@{ customerId = 'tenant-a' }, [pscustomobject]@{ customerId = 'tenant-b' })
        }
        $Result = Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -TenantList
        $Result | Should -Be @('tenant-a')
        Should -Invoke -CommandName Get-Tenants -Times 1
    }

    It 'explicit AllowedTenants does NOT call Get-Tenants, excludes blocked, sorts unique' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith {
            [pscustomobject]@{ Unrestricted = $false; AllowAllTenants = $false; AllowedTenants = @('tenant-c', 'tenant-a', 'tenant-a'); BlockedTenants = @('tenant-b') }
        }
        Mock -CommandName Get-Tenants -MockWith { throw 'Get-Tenants must not be called for explicit AllowedTenants' }
        $Result = Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -TenantList
        $Result | Should -Be @('tenant-a', 'tenant-c')
        Should -Invoke -CommandName Get-Tenants -Times 0
    }
}

Describe 'Test-CIPPAccess per-endpoint custom-role evaluation' {
    BeforeAll {
        $script:CIPPBaseRoles = $script:SeedBaseRoles
        $script:Tenant1 = [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com' }
        $script:Tenant2 = [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 't2.example.com' }
    }

    It 'sticky APIAllowed: role A grants permission but fails tenant scope, role B passes scope -> $true' {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            param($Role)
            switch ($Role) {
                'roleA' { [pscustomobject]@{ Role = 'roleA'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() } }
                'roleB' { [pscustomobject]@{ Role = 'roleB'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-2'); BlockedTenants = @(); BlockedEndpoints = @() } }
                default { throw "unexpected $Role" }
            }
        }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleA', 'roleB') -Query @{ tenantFilter = 'tenant-2' }) | Should -BeTrue
    }

    It 'throws required-permission naming the APIRole when no role grants the permission' {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            [pscustomobject]@{ Role = 'roleX'; Permissions = @('Identity.User.Read'); AllowedTenants = @('AllTenants'); BlockedTenants = @(); BlockedEndpoints = @() }
        }
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleX') -Query @{ tenantFilter = 'tenant-1' }) } |
            Should -Throw -ExpectedMessage '*required permission: Identity.User.ReadWrite*'
    }

    It 'permission granted, tenant not allowed, Functionality AnyTenant -> $true' {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'AnyTenant' } }
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
        }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Query @{ tenantFilter = 'tenant-2' }) | Should -BeTrue
    }

    It 'UNRESOLVED tenantFilter, Functionality AnyTenant -> $true' {
        # Constraint: the unresolved-filter deny must never reach AnyTenant endpoints —
        # the AnyTenant exemption is evaluated after the tenant-scope result, so a
        # filter that maps to no known tenant still passes here (and only here).
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'AnyTenant' } }
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
        }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Query @{ tenantFilter = 'ffffffff-ffff-ffff-ffff-ffffffffffff' }) | Should -BeTrue
    }

    It 'permission granted, tenant not allowed, no AnyTenant -> tenant error' {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
        Mock -CommandName Get-CIPPRolePermissions -MockWith {
            [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
        }
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Query @{ tenantFilter = 'tenant-2' }) } |
            Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
    }

    It 'Get-CIPPRolePermissions throws for every role: with -TenantList -> @()' {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        Mock -CommandName Get-CippAccessScopeRule -MockWith { throw 'no rule' }
        Mock -CommandName Get-CIPPRolePermissions -MockWith { throw 'no perms' }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -TenantList | Should -Be @()
    }

    It 'Get-CIPPRolePermissions throws for every role: without -TenantList -> required-permission throw' {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1) }
        Mock -CommandName Get-CIPPRolePermissions -MockWith { throw 'no perms' }
        { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) } |
            Should -Throw -ExpectedMessage '*does not have the required permission*'
    }
}

Describe 'Test-CIPPAccess tenant-filter permutations' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{
            'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' }
            'Invoke-ListUsers'     = @{ Role = 'Identity.User.Read'; Functionality = 'Entrypoint' }
        }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
        $script:Tenant1 = [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com' }
        $script:Tenant2 = [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 't2.example.com' }
    }
    BeforeEach {
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
    }

    Context 'unmapped tenant filter' {
        It 'DENIES a tenantFilter GUID that maps to no known tenant (unresolved filters fail closed on the allow path)' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Query @{ tenantFilter = 'ffffffff-ffff-ffff-ffff-ffffffffffff' }) } |
                Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
        }

        It 'still ALLOWS an absent tenantFilter for a tenant-restricted role (endpoint is not tenant-scoped)' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1')) | Should -BeTrue
        }
    }

    Context 'AllTenants filter vs Read/Write APIRole' {
        It 'AllTenants + APIRole ending in Read -> allowed even for a tenant-restricted role' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.Read'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'ListUsers' -UserRoles @('roleT1') -Query @{ tenantFilter = 'AllTenants' }) |
                Should -BeTrue
        }

        It 'AllTenants + APIRole ending in Write -> tenant denied for a tenant-restricted role' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Query @{ tenantFilter = 'AllTenants' }) } |
                Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
        }
    }

    Context 'filter precedence' {
        It 'Body.tenantFilter.value (object form) resolves the target when Query has no filter' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            $Body = @{ tenantFilter = [pscustomobject]@{ type = 'Tenant'; value = 'tenant-2'; label = 'T2' } }
            # Body value tenant-2 is outside the role's scope; if the object form did not resolve,
            # the unmapped-filter quirk would allow this instead.
            { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Body $Body) } |
                Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
        }

        It 'Query.tenantFilter wins over Body.tenantFilter when both are present' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'roleT1'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            $Body = @{ tenantFilter = [pscustomobject]@{ type = 'Tenant'; value = 'tenant-2'; label = 'T2' } }
            # Query names the allowed tenant, Body the denied one; allow proves Query precedence.
            Test-CIPPAccess -Request (New-UserRequest -UserRoles @('roleT1') -Query @{ tenantFilter = 'tenant-1' } -Body $Body) |
                Should -BeTrue
        }
    }
}

Describe 'Test-CIPPAccess base and custom role interplay' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{
            'Invoke-ExecResetPass'       = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' }
            'Invoke-ListUsers'           = @{ Role = 'Identity.User.Read'; Functionality = 'Entrypoint' }
            'Invoke-ListSharepointSites' = @{ Role = 'Sharepoint.Site.Read'; Functionality = 'Entrypoint' }
        }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
        $script:Tenant1 = [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 't1.example.com' }
        $script:Tenant2 = [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 't2.example.com' }
    }
    BeforeEach {
        Mock -CommandName Get-Tenants -MockWith { @($script:Tenant1, $script:Tenant2) }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { @() }
    }

    Context 'custom roles narrow base roles' {
        It 'editor + custom role: endpoint the base allows but the custom role does not grant -> required-permission throw' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'customrole'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('AllTenants'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            { Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'ListSharepointSites' -UserRoles @('editor', 'customrole') -Query @{ tenantFilter = 'tenant-1' }) } |
                Should -Throw -ExpectedMessage '*required permission: Sharepoint.Site.Read*'
        }

        It 'editor + custom role: granted endpoint but tenant outside the custom scope -> tenant error' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'customrole'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('tenant-1'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            { Test-CIPPAccess -Request (New-UserRequest -UserRoles @('editor', 'customrole') -Query @{ tenantFilter = 'tenant-2' }) } |
                Should -Throw -ExpectedMessage '*Access to this tenant is not allowed*'
        }

        It 'control: editor alone has NO tenant restriction and never consults custom-role permissions' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith { throw 'must not be consulted for a base-only user' }
            Test-CIPPAccess -Request (New-UserRequest -UserRoles @('editor') -Query @{ tenantFilter = 'tenant-2' }) | Should -BeTrue
            Should -Invoke -CommandName Get-CIPPRolePermissions -Times 0
        }
    }

    Context 'permission regex semantics' {
        It 'a role granting only Identity.User.ReadWrite satisfies APIRole Identity.User.Read (substring regex match; load-bearing)' {
            # $Perm -match $APIRole: 'Identity.User.ReadWrite' contains 'Identity.User.Read', so ReadWrite implies Read.
            Mock -CommandName Get-CIPPRolePermissions -MockWith {
                [pscustomobject]@{ Role = 'customrole'; Permissions = @('Identity.User.ReadWrite'); AllowedTenants = @('AllTenants'); BlockedTenants = @(); BlockedEndpoints = @() }
            }
            Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'ListUsers' -UserRoles @('customrole') -Query @{ tenantFilter = 'tenant-1' }) |
                Should -BeTrue
        }
    }

    Context 'role collapse shortcuts' {
        It 'superadmin who also has custom roles returns $true via the shortcut; custom-role scoping never evaluated' {
            Mock -CommandName Get-CIPPRolePermissions -MockWith { throw 'must not be consulted for superadmin' }
            Test-CIPPAccess -Request (New-UserRequest -UserRoles @('superadmin', 'customrole') -Query @{ tenantFilter = 'tenant-1' }) |
                Should -BeTrue
            Should -Invoke -CommandName Get-CIPPRolePermissions -Times 0
        }
    }

    Context 'unknown endpoint (APIRole resolves to $null)' {
        # Not in $script:CIPPFunctionPermissions and Get-Help fails -> $APIRole stays $null.
        It 'admin base role allows an unknown endpoint ($null -like ''*'' is true)' {
            Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'NoSuchEndpoint' -UserRoles @('admin')) 3>$null |
                Should -BeTrue
        }

        It 'readonly base role denies an unknown endpoint ($null -like ''*.Read'' is false)' {
            { Test-CIPPAccess -Request (New-UserRequest -CIPPEndpoint 'NoSuchEndpoint' -UserRoles @('readonly')) 3>$null } |
                Should -Throw -ExpectedMessage '*base role does not have the required permission*'
        }
    }
}

Describe 'Test-CIPPAccess scope-rule permutations' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'mixed rules: Unrestricted + explicit AllowedTenants -> union contains AllTenants AND the explicit IDs' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith {
            param($Role)
            switch ($Role) {
                'openrole' { [pscustomobject]@{ Unrestricted = $true } }
                'scopedrole' { [pscustomobject]@{ Unrestricted = $false; AllowAllTenants = $false; AllowedTenants = @('tenant-y', 'tenant-x'); BlockedTenants = @() } }
                default { throw "unexpected $Role" }
            }
        }
        Mock -CommandName Get-Tenants -MockWith { throw 'Get-Tenants must not be called (no AllowAllTenants rule)' }
        $Result = Test-CIPPAccess -Request (New-UserRequest -UserRoles @('openrole', 'scopedrole')) -TenantList
        $Result | Should -Be @('AllTenants', 'tenant-x', 'tenant-y')
        Should -Invoke -CommandName Get-Tenants -Times 0
    }

    It '-GroupList with a non-unrestricted rule returns its AllowedGroups sorted unique' {
        Mock -CommandName Get-CippAccessScopeRule -MockWith {
            [pscustomobject]@{ Unrestricted = $false; AllowedGroups = @('group-b', 'group-a', 'group-a') }
        }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('customrole')) -GroupList | Should -Be @('group-a', 'group-b')
    }
}

Describe 'Test-CIPPAccess IP quirks' {
    BeforeAll {
        $script:CIPPFunctionPermissions = @{ 'Invoke-ExecResetPass' = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' } }
        $script:CIPPBaseRoles = $script:SeedBaseRoles
    }

    It 'restrictive role IP range with NO x-forwarded-for header -> allowed (empty IP fail-open quirk)' {
        # No header -> parsed IP is '' -> the if($IPAddress) guard skips matching and sets IPAllowed = $true.
        Mock -CommandName Get-CIPPRoleIPRanges -MockWith { @('10.0.0.0/24') }
        Mock -CommandName Test-IpInRange -MockWith { throw 'must not be called with an empty IP' }
        Test-CIPPAccess -Request (New-UserRequest -UserRoles @('editor') -OmitForwardedFor) | Should -BeTrue
        Should -Invoke -CommandName Test-IpInRange -Times 0
    }
}
