# Expected access behaviour for users holding several roles, written out case by case: custom-role
# combinations, custom roles mixed with the built-in roles, blocked tenants and blocked endpoints.
# Test-CIPPAccess.RoleMatrix.Exhaustive.Tests.ps1 checks every combination against a reference model.

BeforeDiscovery {
    # Write = Identity.User.ReadWrite (ExecResetPass), Read = Identity.User.Read (ListUsers).
    $script:Cases = @(
        # one role
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = 't1.example.com'; Expect = 'allow' }
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-t1'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('w-t1'); Op = 'Read'; Filter = 'AllTenants'; Expect = 'allow' }
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'unknown-tenant'; Expect = 'deny' }
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = $null; Expect = 'allow' }
        @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'group:g12'; Expect = 'deny' }
        @{ Roles = @('r-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('r-t2'); Op = 'Read'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('r-t2'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('none-t1'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-all'); Op = 'Write'; Filter = 'tenant-3'; Expect = 'allow' }
        @{ Roles = @('w-all'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'allow' }
        @{ Roles = @('w-all-block-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-all-block-t2'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-all-block-t2'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('w-all-block-t2'); Op = 'Read'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-g12'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('w-g12'); Op = 'Write'; Filter = 'tenant-3'; Expect = 'deny' }
        @{ Roles = @('w-g12'); Op = 'Write'; Filter = 'group:g12'; Expect = 'allow' }
        @{ Roles = @('w-g12'); Op = 'Write'; Filter = 'group:g3'; Expect = 'deny' }
        @{ Roles = @('w-t1-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-t1-blockep'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'allow' }

        # a role with no allowed tenants reaches none
        @{ Roles = @('w-empty'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-empty'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-empty'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('w-empty'); Op = 'Write'; Filter = 'group:g12'; Expect = 'deny' }
        @{ Roles = @('w-empty', 'w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-empty', 'w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('editor', 'w-empty'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('readonly', 'w-empty'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('admin', 'w-empty'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }

        # write on one tenant + read on another never adds up to write on the second
        @{ Roles = @('w-t1', 'r-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('r-t2', 'w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-t2'); Op = 'Write'; Filter = 't2.example.com'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-t2'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'r-t2'); Op = 'Read'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Filter = 'tenant-3'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('r-all', 'w-t1'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Read'; Filter = 'tenant-3'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'r-g3'); Op = 'Write'; Filter = 'group:g3'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-g3'); Op = 'Read'; Filter = 'group:g3'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'none-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }

        # two roles that both grant the permission add up
        @{ Roles = @('w-t1', 'w-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('w-t2', 'w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'w-t2'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'w-all-block-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'w-all-block-t2'); Op = 'Write'; Filter = 'tenant-3'; Expect = 'allow' }

        # a blocked endpoint wins over another role allowing it, wherever the blocking role reaches
        @{ Roles = @('w-all', 'w-t1-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-t1-blockep', 'w-all'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-all', 'w-t1-blockep'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'w-all-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-all-blockep', 'w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-all-blockep', 'w-t1'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-g12', 'w-t1-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-g12', 'w-t1-blockep'); Op = 'Write'; Filter = 'group:g12'; Expect = 'deny' }
        @{ Roles = @('w-g12', 'w-t1-blockep'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('w-all', 'w-g12-blockep'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-g12-blockep', 'w-all'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-all', 'w-g12-blockep'); Op = 'Write'; Filter = 'group:g12'; Expect = 'deny' }
        @{ Roles = @('w-all', 'w-g12-blockep'); Op = 'Write'; Filter = 'tenant-3'; Expect = 'allow' }

        # built-in roles
        @{ Roles = @('readonly'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('readonly'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('editor'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('editor'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'allow' }
        @{ Roles = @('editor'); Op = 'Standards'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('admin'); Op = 'Standards'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('admin'); Op = 'SuperAdmin'; Filter = $null; Expect = 'deny' }
        @{ Roles = @('superadmin'); Op = 'SuperAdmin'; Filter = $null; Expect = 'allow' }
        @{ Roles = @('readonly', 'editor'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('editor', 'readonly'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }

        # built-in role + custom roles: the built-in role caps the permission, the custom roles set the tenants
        @{ Roles = @('readonly', 'w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'readonly'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('readonly', 'w-t1'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('editor', 'w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('editor', 'w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('editor', 'w-t1'); Op = 'Write'; Filter = 'AllTenants'; Expect = 'deny' }
        @{ Roles = @('editor', 'r-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('editor', 'r-t1'); Op = 'Read'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('editor', 'r-t1'); Op = 'Read'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('editor', 'w-t1'); Op = 'Read'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('editor', 'w-t1'); Op = 'Standards'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('admin', 'w-t1-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('admin', 'r-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('superadmin', 'w-all-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }

        # AllTenants read-only + write on one tenant
        @{ Roles = @('r-all', 'w-t1'); Op = 'Read'; Filter = 'tenant-3'; Expect = 'allow' }
        @{ Roles = @('r-all', 'w-t1'); Op = 'Read'; Filter = 'AllTenants'; Expect = 'allow' }
        @{ Roles = @('r-all', 'w-t1'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Filter = 'tenant-1'; Expect = 'allow' }
        @{ Roles = @('r-all', 'w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Filter = 'group:g12'; Expect = 'deny' }
        @{ Roles = @('editor', 'w-t1', 'r-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'deny' }
        @{ Roles = @('editor', 'w-all'); Op = 'Standards'; Filter = 'tenant-1'; Expect = 'deny' }
        @{ Roles = @('admin', 'w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('w-t1', 'admin'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'allow' }
        @{ Roles = @('superadmin', 'r-t1'); Op = 'Write'; Filter = 'tenant-3'; Expect = 'allow' }
    )

    # The tenant list a request is scoped to, for the endpoint being called. Only requests the caller
    # may make at all: New-CippCoreRequest builds the list after Test-CIPPAccess has let the request in.
    $script:ListCases = @(
        @{ Roles = @('w-t1', 'r-t2'); Op = 'Write'; Expect = @('tenant-1') }
        @{ Roles = @('r-t2', 'w-t1'); Op = 'Write'; Expect = @('tenant-1') }
        @{ Roles = @('w-t1', 'r-t2'); Op = 'Read'; Expect = @('tenant-1', 'tenant-2') }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Expect = @('tenant-1') }
        @{ Roles = @('w-t1', 'r-all'); Op = 'Read'; Expect = @('AllTenants') }
        @{ Roles = @('r-all', 'w-t1'); Op = 'Write'; Expect = @('tenant-1') }
        @{ Roles = @('r-all', 'w-t1'); Op = 'Read'; Expect = @('AllTenants') }
        @{ Roles = @('w-all', 'w-g12-blockep'); Op = 'Write'; Expect = @('tenant-3') }
        @{ Roles = @('w-all-block-t2'); Op = 'Write'; Expect = @('tenant-1', 'tenant-3') }
        @{ Roles = @('w-empty'); Op = 'Write'; Expect = @() }
        @{ Roles = @('w-empty'); Op = 'Read'; Expect = @() }
        @{ Roles = @('w-empty', 'w-t1'); Op = 'Write'; Expect = @('tenant-1') }
        @{ Roles = @('editor', 'w-empty'); Op = 'Write'; Expect = @() }
        @{ Roles = @('w-g12'); Op = 'Write'; Expect = @('tenant-1', 'tenant-2') }
        @{ Roles = @('w-t1', 'w-t2'); Op = 'Write'; Expect = @('tenant-1', 'tenant-2') }
        @{ Roles = @('w-all', 'w-t1-blockep'); Op = 'Write'; Expect = @('tenant-2', 'tenant-3') }
        @{ Roles = @('w-all-blockep', 'w-t1'); Op = 'Read'; Expect = @('AllTenants') }
        @{ Roles = @('editor'); Op = 'Write'; Expect = @('AllTenants') }
        @{ Roles = @('readonly'); Op = 'Read'; Expect = @('AllTenants') }
        @{ Roles = @('readonly', 'w-t1'); Op = 'Read'; Expect = @('tenant-1') }
        @{ Roles = @('editor', 'w-t1', 'r-t2'); Op = 'Write'; Expect = @('tenant-1') }
        @{ Roles = @('admin', 'w-t1'); Op = 'Write'; Expect = @('AllTenants') }
    )
    $script:GroupListCases = @(
        @{ Roles = @('w-g12'); Op = 'Write'; Expect = @('g12') }
        @{ Roles = @('w-g12', 'r-g3'); Op = 'Write'; Expect = @('g12') }
        @{ Roles = @('w-g12', 'r-g3'); Op = 'Read'; Expect = @('g12', 'g3') }
        @{ Roles = @('w-t1', 'r-g3'); Op = 'Write'; Expect = @() }
    )
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication'
    $PrivateAuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Private/Authentication'

    class HttpResponseContext { [int]$StatusCode; [object]$Body; [object]$ContentType }

    function Get-CippApiClient { param($AppId) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    function Get-CIPPRolePermissions { param($Role) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-CIPPRoleIPRanges { param($Roles) @('Any') }
    function Test-CIPPAccessUserRole { param($User) $User }
    function Resolve-CippImpersonation { param($User, $Request) [pscustomobject]@{ User = $User; Impersonating = $null; RealRoles = $User.userRoles } }
    function Get-CippAllowedPermissions { param($UserRoles) @() }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Get-CippAccessScopeVersion { 'v1' }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $user, $LogData) }

    . (Join-Path $AuthDir 'Test-CippRoleTenantScope.ps1')
    . (Join-Path $AuthDir 'Test-CIPPAccess.ps1')
    . (Join-Path $AuthDir 'Assert-CippTenantAccess.ps1')
    . (Join-Path $AuthDir 'Get-CippAccessScopeRule.ps1')
    . (Join-Path $AuthDir 'Expand-CippScopeTenantItem.ps1')
    . (Join-Path $PrivateAuthDir 'Find-CippBaseRole.ps1')
    . (Join-Path $PrivateAuthDir 'Get-CippRequestIPAddress.ps1')
    . (Join-Path $PrivateAuthDir 'New-CippMeResponse.ps1')

    $script:CIPPBaseRoles = [pscustomobject]@{
        readonly   = [pscustomobject]@{ include = @('*.Read'); exclude = @('CIPP.SuperAdmin.*', 'CIPP.Admin.*', 'CIPP.AppSettings.*') }
        editor     = [pscustomobject]@{ include = @('*.Read', '*.ReadWrite'); exclude = @('CIPP.SuperAdmin.*', 'CIPP.Admin.*', 'CIPP.AppSettings.*', 'Tenant.Standards.ReadWrite') }
        admin      = [pscustomobject]@{ include = @('*'); exclude = @('CIPP.SuperAdmin.*') }
        superadmin = [pscustomobject]@{ include = @('*'); exclude = @() }
    }
    $script:Endpoints = @{
        Write      = 'ExecResetPass'
        Read       = 'ListUsers'
        Standards  = 'ExecStandardThing'
        SuperAdmin = 'ExecSuperThing'
        AnyWrite   = 'AddThingApp'
    }
    $script:CIPPFunctionPermissions = @{
        'Invoke-ExecResetPass'     = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint' }
        'Invoke-ListUsers'         = @{ Role = 'Identity.User.Read'; Functionality = 'Entrypoint' }
        'Invoke-ExecStandardThing' = @{ Role = 'Tenant.Standards.ReadWrite'; Functionality = 'Entrypoint' }
        'Invoke-ExecSuperThing'    = @{ Role = 'CIPP.SuperAdmin.ReadWrite'; Functionality = 'Entrypoint' }
        'Invoke-AddThingApp'       = @{ Role = 'Identity.User.ReadWrite'; Functionality = 'Entrypoint,AnyTenant' }
    }

    $script:Tenants = @(1..3 | ForEach-Object { [pscustomobject]@{ customerId = "tenant-$_"; defaultDomainName = "t$_.example.com"; initialDomainName = "t$_.onmicrosoft.com" } })
    $script:GroupMembers = @{ g12 = @('tenant-1', 'tenant-2'); g3 = @('tenant-3') }

    # Permissions are what Get-CIPPRolePermissions returns after expanding the role's rules:
    # a ReadWrite grant always carries the matching Read.
    $RW = @('Identity.User.Read', 'Identity.User.ReadWrite', 'Tenant.Standards.Read', 'Tenant.Standards.ReadWrite')
    $RO = @('Identity.User.Read', 'Tenant.Standards.Read')
    function New-Role($Name, $Permissions, $Allowed, $Blocked = @(), $BlockedEndpoints = @()) {
        [pscustomobject]@{ Role = $Name; Permissions = @($Permissions); AllowedTenants = @($Allowed); BlockedTenants = @($Blocked); BlockedEndpoints = @($BlockedEndpoints) }
    }
    function New-GroupItem($Id) { [pscustomobject]@{ type = 'Group'; value = $Id; label = $Id } }
    $script:RoleDefs = @{
        'w-t1'           = New-Role 'w-t1' $RW @('tenant-1')
        'w-t2'           = New-Role 'w-t2' $RW @('tenant-2')
        'r-t1'           = New-Role 'r-t1' $RO @('tenant-1')
        'r-t2'           = New-Role 'r-t2' $RO @('tenant-2')
        'r-all'          = New-Role 'r-all' $RO @('AllTenants')
        'w-all'          = New-Role 'w-all' $RW @('AllTenants')
        'w-all-block-t2' = New-Role 'w-all-block-t2' $RW @('AllTenants') @('tenant-2')
        'w-g12'          = New-Role 'w-g12' $RW @((New-GroupItem 'g12'))
        'r-g3'           = New-Role 'r-g3' $RO @((New-GroupItem 'g3'))
        'w-g12-no2'      = New-Role 'w-g12-no2' $RW @((New-GroupItem 'g12')) @('tenant-2')
        'w-t1-blockep'   = New-Role 'w-t1-blockep' $RW @('tenant-1') @() @('ExecResetPass')
        'w-all-blockep'  = New-Role 'w-all-blockep' $RW @('AllTenants') @() @('ExecResetPass')
        'w-g12-blockep'  = New-Role 'w-g12-blockep' $RW @((New-GroupItem 'g12')) @() @('ExecResetPass')
        'none-t1'        = New-Role 'none-t1' @('CIPP.Core.Read') @('tenant-1')
        'w-empty'        = New-Role 'w-empty' $RW @()
    }

    function New-RoleRequest {
        param([string[]]$Roles, [string]$Op, $Filter, [hashtable]$Query = @{}, [hashtable]$Body = @{})
        if ($Filter -like 'group:*') {
            $Body['tenantFilter'] = [pscustomobject]@{ type = 'Group'; value = $Filter.Substring(6); label = $Filter }
        } elseif ($Filter) {
            $Query['tenantFilter'] = $Filter
        }
        $Principal = @{ identityProvider = 'aad'; userId = 'u1'; userDetails = 'user@contoso.com'; userRoles = @('authenticated') + $Roles } | ConvertTo-Json -Compress
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = $script:Endpoints[$Op] }
            Headers = @{
                'x-ms-client-principal'      = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Principal))
                'x-ms-client-principal-name' = 'user@contoso.com'
                'x-forwarded-for'            = '1.2.3.4'
            }
            Query   = $Query
            Body    = $Body
        }
    }
    function Get-AccessDecision {
        param([string[]]$Roles, [string]$Op, $Filter, [hashtable]$Query = @{}, [hashtable]$Body = @{})
        try {
            $null = Test-CIPPAccess -Request (New-RoleRequest -Roles $Roles -Op $Op -Filter $Filter -Query $Query -Body $Body)
            'allow'
        } catch {
            'deny'
        }
    }
    function Get-ScopeList {
        param([string[]]$Roles, [string]$Op, [switch]$Groups)
        $Request = New-RoleRequest -Roles $Roles -Op $Op -Filter $null
        # A caller refused the endpoint outright never gets a list built; record that instead.
        $List = try {
            if ($Groups) { Test-CIPPAccess -Request $Request -GroupList } else { Test-CIPPAccess -Request $Request -TenantList }
        } catch {
            return @('<refused>')
        }
        # Consumers treat any list holding AllTenants/AllGroups as unrestricted.
        if (@($List) -contains 'AllTenants') { return @('AllTenants') }
        if (@($List) -contains 'AllGroups') { return @('AllGroups') }
        @($List | Sort-Object -Unique)
    }
}

Describe 'Test-CIPPAccess with combined roles' {
    BeforeEach {
        $script:CippAccessScopeRuleCache = @{}
        Mock Get-Tenants { $script:Tenants }
        Mock Get-CIPPRolePermissions {
            param($Role)
            if (-not $script:RoleDefs.ContainsKey($Role)) { throw "Role $Role not found." }
            $script:RoleDefs[$Role]
        }
        Mock Expand-CIPPTenantGroups {
            param($TenantFilter)
            foreach ($Id in $script:GroupMembers["$(@($TenantFilter)[0].value)"]) { [pscustomobject]@{ addedFields = [pscustomobject]@{ customerId = $Id } } }
        }
    }

    Context 'expected decisions' {
        It '<Roles> -> <Op> on <Filter> is <Expect>' -ForEach $script:Cases {
            Get-AccessDecision -Roles $Roles -Op $Op -Filter $Filter | Should -Be $Expect
        }
    }

    Context 'every tenant named in the request is checked' {
        It 'denies when the query names an allowed tenant and the body another' {
            Get-AccessDecision -Roles @('w-t1') -Op 'Write' -Filter 'tenant-1' -Body @{ tenantFilter = 'tenant-2' } | Should -Be 'deny'
        }
        It 'denies when tenantFilter is allowed but tenantId names another tenant' {
            Get-AccessDecision -Roles @('w-t1') -Op 'Write' -Filter $null -Body @{ tenantFilter = 'tenant-1'; tenantId = 'tenant-2' } | Should -Be 'deny'
        }
        It 'allows when every tenant named is allowed' {
            Get-AccessDecision -Roles @('w-t1') -Op 'Write' -Filter 'tenant-1' -Body @{ tenantFilter = 'tenant-1' } | Should -Be 'allow'
        }
    }

    Context 'a refusal says why, naming only what the caller asked for' {
        It '<Roles> -> <Op> on <Filter>: <Expect>' -ForEach @(
            @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'tenant-2'; Expect = "Your roles don't include t2.example.com. Ask an admin to add it to one of your roles." }
            @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'unknown-tenant'; Expect = "Your roles don't include unknown-tenant. Ask an admin to add it to one of your roles." }
            @{ Roles = @('w-t1', 'r-all'); Op = 'Write'; Filter = 'unknown-tenant'; Expect = "Your roles don't include unknown-tenant. Ask an admin to add it to one of your roles." }
            @{ Roles = @('w-t1', 'r-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = "You can view t2.example.com but not change it. This action needs Identity.User.ReadWrite, which your roles don't grant for that tenant." }
            @{ Roles = @('none-t1', 'w-t2'); Op = 'Read'; Filter = 'tenant-1'; Expect = "Your roles include t1.example.com, but not the Identity.User.Read permission this action needs there." }
            @{ Roles = @('w-all-block-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = "Your role 'w-all-block-t2' excludes t2.example.com." }
            @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'AllTenants'; Expect = "Your roles don't allow this on all tenants at once. Pick a tenant instead, or ask an admin to change your roles." }
            @{ Roles = @('w-t1'); Op = 'Write'; Filter = 'group:g12'; Expect = "Your roles don't include the tenant group 'group:g12'. Ask an admin to add it to one of your roles." }
            @{ Roles = @('w-t1', 'r-g3'); Op = 'Write'; Filter = 'group:g3'; Expect = "You can view the tenant group 'group:g3' but not change it. This action needs Identity.User.ReadWrite, which your roles don't grant for that group." }
            @{ Roles = @('w-g12-no2'); Op = 'Write'; Filter = 'group:g12'; Expect = "Your role 'w-g12-no2' excludes a tenant in the tenant group 'group:g12'." }
            @{ Roles = @('w-t1-blockep'); Op = 'Write'; Filter = 'tenant-1'; Expect = "Your role 'w-t1-blockep' blocks ExecResetPass on t1.example.com." }
            @{ Roles = @('w-t1-blockep'); Op = 'Write'; Filter = $null; Expect = "Your role 'w-t1-blockep' blocks ExecResetPass." }
            @{ Roles = @('r-t2'); Op = 'Write'; Filter = 'tenant-2'; Expect = 'Access to this CIPP API endpoint is not allowed, you do not have the required permission: Identity.User.ReadWrite' }
        ) {
            { Test-CIPPAccess -Request (New-RoleRequest -Roles $Roles -Op $Op -Filter $Filter) } | Should -Throw -ExpectedMessage $Expect
        }
    }

    Context 'tenants an AnyTenant endpoint checks itself' {
        It 'the dispatcher lets an AnyTenant endpoint through whatever tenant it names' {
            Get-AccessDecision -Roles @('w-t1') -Op 'AnyWrite' -Filter 'tenant-2' | Should -Be 'allow'
        }
        It '<Roles> on <Targets> is <Expect>' -ForEach @(
            @{ Roles = @('w-t1'); Targets = @('t1.example.com'); Expect = 'allow' }
            @{ Roles = @('w-t1'); Targets = @('tenant-1'); Expect = 'allow' }
            @{ Roles = @('w-t1'); Targets = @('t1.example.com', 't2.example.com'); Expect = "Your roles don't include t2.example.com. Ask an admin to add it to one of your roles." }
            @{ Roles = @('w-t1'); Targets = @('AllTenants'); Expect = "Your roles don't allow this on all tenants at once. Pick a tenant instead, or ask an admin to change your roles." }
            @{ Roles = @('w-t1', 'r-t2'); Targets = @('t2.example.com'); Expect = "You can view t2.example.com but not change it. This action needs Identity.User.ReadWrite, which your roles don't grant for that tenant." }
            @{ Roles = @('w-g12'); Targets = @('group:g12'); Expect = 'allow' }
            @{ Roles = @('w-t1'); Targets = @('group:g12'); Expect = "Your roles don't include the tenant group 'g12'. Ask an admin to add it to one of your roles." }
            @{ Roles = @('w-g12-no2'); Targets = @('group:g12'); Expect = "Your role 'w-g12-no2' excludes a tenant in the tenant group 'g12'." }
            @{ Roles = @('w-all-block-t2'); Targets = @('t1.example.com', 't3.example.com'); Expect = 'allow' }
            @{ Roles = @('w-all-block-t2'); Targets = @('t2.example.com'); Expect = "Your role 'w-all-block-t2' excludes t2.example.com." }
            @{ Roles = @('editor'); Targets = @('AllTenants'); Expect = 'allow' }
            @{ Roles = @('admin', 'w-t1'); Targets = @('t3.example.com'); Expect = 'allow' }
            @{ Roles = @('w-t1'); Targets = @(); Expect = 'allow' }
        ) {
            $Selectors = @(foreach ($Target in $Targets) { if ($Target -like 'group:*') { New-GroupItem $Target.Substring(6) } else { [pscustomobject]@{ value = $Target; label = $Target } } })
            $Request = New-RoleRequest -Roles $Roles -Op 'AnyWrite' -Filter $null
            $Decision = try { Assert-CippTenantAccess -Request $Request -TenantFilter $Selectors; 'allow' } catch { $_.Exception.Message }
            $Decision | Should -Be $Expect
        }
        It 'refuses with an UnauthorizedAccessException' {
            { Assert-CippTenantAccess -Request (New-RoleRequest -Roles @('w-t1') -Op 'AnyWrite' -Filter $null) -TenantFilter @('t2.example.com') } | Should -Throw -ExceptionType ([System.UnauthorizedAccessException])
        }
        It 'decides against every tenant and puts the request scope back afterwards' {
            $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()
            $script:CippAllowedTenantsStorage.Value = @('tenant-1')
            $script:SeenScope = 'unset'
            Mock Get-Tenants { $script:SeenScope = $script:CippAllowedTenantsStorage.Value; $script:Tenants }
            try {
                { Assert-CippTenantAccess -Request (New-RoleRequest -Roles @('w-all-block-t2') -Op 'AnyWrite' -Filter $null) -TenantFilter @('t2.example.com') } | Should -Throw
                $script:SeenScope | Should -BeNullOrEmpty
                $script:CippAllowedTenantsStorage.Value | Should -Be @('tenant-1')
            } finally {
                $script:CippAllowedTenantsStorage = $null
            }
        }
    }

    Context 'API clients follow the same rules' {
        It '<Role> client -> Write on <Filter> is <Expect>' -ForEach @(
            @{ Role = 'w-t1'; Filter = 'tenant-1'; Expect = 'allow' }
            @{ Role = 'w-t1'; Filter = 'tenant-2'; Expect = 'deny' }
            @{ Role = 'r-all'; Filter = 'tenant-1'; Expect = 'deny' }
            @{ Role = 'editor'; Filter = 'tenant-2'; Expect = 'allow' }
            @{ Role = 'readonly'; Filter = 'tenant-2'; Expect = 'deny' }
        ) {
            Mock Get-CippApiClient { [pscustomobject]@{ AppName = 'client'; Role = $Role; IPRange = @('Any') } }
            $Request = [pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecResetPass' }
                Headers = @{ 'x-ms-client-principal-idp' = 'aad'; 'x-ms-client-principal-name' = '11111111-1111-1111-1111-111111111111'; 'x-forwarded-for' = '1.2.3.4' }
                Query   = @{ tenantFilter = $Filter }
                Body    = @{}
            }
            $Decision = try { $null = Test-CIPPAccess -Request $Request; 'allow' } catch { 'deny' }
            $Decision | Should -Be $Expect
        }
    }

    Context 'the tenant list for a request' {
        It '<Roles> -> <Op> tenant list is <Expect>' -ForEach $script:ListCases {
            Get-ScopeList -Roles $Roles -Op $Op | Should -Be $Expect
        }
        It '<Roles> -> <Op> group list is <Expect>' -ForEach $script:GroupListCases {
            Get-ScopeList -Roles $Roles -Op $Op -Groups | Should -Be $Expect
        }
    }
}

Describe 'Endpoint permission names' {
    It 'no permission satisfies another endpoint''s role except its own ReadWrite covering Read' {
        # The dispatcher compares with an unanchored -match, so a name that contains another one would grant it.
        $ModulesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
        $Roles = Get-ChildItem $ModulesRoot -Recurse -Filter 'Invoke-*.ps1' | ForEach-Object {
            if ((Get-Content $_.FullName -Raw) -match '\.ROLE\s*\r?\n\s*([A-Za-z0-9.]+)') { $Matches[1] }
        } | Sort-Object -Unique
        $Roles.Count | Should -BeGreaterThan 50
        $Collisions = foreach ($Required in $Roles) {
            foreach ($Granted in $Roles) {
                if ($Granted -ne $Required -and $Granted -match $Required -and $Granted -ne ($Required -replace '\.Read$', '.ReadWrite')) { "$Granted satisfies $Required" }
            }
        }
        $Collisions | Should -BeNullOrEmpty
    }
}
