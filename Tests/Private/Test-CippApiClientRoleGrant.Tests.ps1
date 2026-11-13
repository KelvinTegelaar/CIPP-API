# Pester tests for Test-CippApiClientRoleGrant: permission subset and tenant reach.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippApiClient { param($AppId) }
    function Get-CIPPAccessRole { param($Request) }
    function Get-CippAllowedPermissions { param($UserRoles) }
    function Get-CIPPRolePermissions { param($RoleName) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Test-CippApiClientRoleGrant.ps1')

    $script:Request = [pscustomobject]@{ Headers = @{}; Params = @{ CIPPEndpoint = 'ExecApiClient' } }
    $script:Permissions = @{
        readonly      = @('A.Read', 'CIPP.Extension.Read')
        editor        = @('A.Read', 'A.ReadWrite', 'CIPP.Extension.Read', 'CIPP.Extension.ReadWrite')
        admin         = @('A.Read', 'A.ReadWrite', 'CIPP.Extension.Read', 'CIPP.Extension.ReadWrite', 'CIPP.AppSettings.ReadWrite')
        'tenant-one'  = @('A.Read', 'A.ReadWrite', 'CIPP.Extension.Read', 'CIPP.Extension.ReadWrite')
        'tenant-read' = @('A.Read')
    }
}

Describe 'Test-CippApiClientRoleGrant' {
    BeforeEach {
        $script:CallerRoles = @('tenant-one')
        $script:CallerTenants = @('11111111-1111-1111-1111-111111111111')
        Mock Get-CIPPAccessRole { $script:CallerRoles }
        Mock Test-CIPPAccess { $script:CallerTenants }
        Mock Get-CIPPRolePermissions { }
        Mock Get-CippAllowedPermissions {
            $Set = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($Role in $UserRoles) { foreach ($Permission in $script:Permissions[$Role]) { $null = $Set.Add($Permission) } }
            @($Set)
        }
    }

    Context 'a caller limited to some tenants' {
        It 'cannot assign the built-in <_> role, which has no tenant limit' -ForEach @('readonly', 'editor') {
            (Test-CippApiClientRoleGrant -Request $script:Request -Role $_).Allowed | Should -BeFalse
        }

        It 'cannot assign a built-in role it holds alongside its custom role' {
            $script:CallerRoles = @('editor', 'tenant-one')
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'editor').Allowed | Should -BeFalse
        }

        It 'cannot assign another custom role, even one with fewer permissions' {
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'tenant-read').Allowed | Should -BeFalse
        }

        It 'cannot manage a client that has no role' {
            (Test-CippApiClientRoleGrant -Request $script:Request -Role '').Allowed | Should -BeFalse
        }

        It 'can assign its own custom role' {
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'tenant-one').Allowed | Should -BeTrue
        }

        It 'is refused when its tenant access cannot be resolved' {
            Mock Test-CIPPAccess { throw 'boom' }
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'tenant-one').Allowed | Should -BeFalse
        }
    }

    Context 'a caller with access to all tenants' {
        BeforeEach {
            $script:CallerRoles = @('editor')
            $script:CallerTenants = @('AllTenants')
        }

        It 'can assign a role within its permissions' {
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'readonly').Allowed | Should -BeTrue
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'tenant-read').Allowed | Should -BeTrue
        }

        It 'cannot assign a role beyond its permissions' {
            (Test-CippApiClientRoleGrant -Request $script:Request -Role 'admin').Allowed | Should -BeFalse
        }
    }

    It 'lets a superadmin assign anything without a tenant lookup' {
        $script:CallerRoles = @('superadmin')
        (Test-CippApiClientRoleGrant -Request $script:Request -Role 'admin').Allowed | Should -BeTrue
        Should -Invoke Test-CIPPAccess -Times 0 -Exactly
    }
}
