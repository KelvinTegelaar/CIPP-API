BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPRolePermissions { param($RoleName) }
    function Write-LogMessage { param($message, $tenant, $API, $headers, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Resolve-CippImpersonation.ps1')

    $script:MakeUser = {
        param($Roles)
        [pscustomobject]@{
            identityProvider = 'aad'
            userId           = '00000000-0000-0000-0000-000000000001'
            userDetails      = 'superadmin@test.local'
            userRoles        = $Roles
        }
    }
    $script:MakeRequest = {
        param($Role)
        [pscustomobject]@{ Headers = [pscustomobject]@{ 'x-cipp-impersonate-role' = $Role } }
    }
}

Describe 'Resolve-CippImpersonation' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Get-CIPPRolePermissions { [pscustomobject]@{ Role = $RoleName } }
        # per-worker audit dedupe must not leak between tests
        $script:CippImpersonationLogged = $null
    }

    It 'returns the original user when no header is present' {
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'superadmin')
        $Result = Resolve-CippImpersonation -User $User -Request ([pscustomobject]@{ Headers = [pscustomobject]@{} })
        $Result.Impersonating | Should -BeNullOrEmpty
        $Result.User | Should -Be $User
    }

    It 'ignores the header for non-superadmins (no privilege change, no throw)' {
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'editor')
        $Result = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'admin') -WarningAction SilentlyContinue
        $Result.Impersonating | Should -BeNullOrEmpty
        $Result.User.userRoles | Should -Be @('anonymous', 'authenticated', 'editor')
        Should -Invoke Write-LogMessage -Times 0
    }

    It 'swaps a superadmin to a base role without touching the original object' {
        $OriginalRoles = @('anonymous', 'authenticated', 'superadmin')
        $User = & $script:MakeUser $OriginalRoles
        $Result = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'readonly')

        $Result.Impersonating | Should -Be 'readonly'
        $Result.User.userRoles | Should -Be @('authenticated', 'anonymous', 'readonly')
        $Result.RealRoles | Should -Be @('superadmin')
        # Reference safety: the cached roles array of the real user must be untouched.
        $User.userRoles | Should -Be $OriginalRoles
        # Base roles skip the table read entirely.
        Should -Invoke Get-CIPPRolePermissions -Times 0
    }

    It 'throws when the target is superadmin' {
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'superadmin')
        { Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'superadmin') } |
            Should -Throw '*not allowed*'
    }

    It 'validates custom roles via Get-CIPPRolePermissions and swaps on success' {
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'superadmin')
        $Result = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'helpdesk')
        $Result.Impersonating | Should -Be 'helpdesk'
        Should -Invoke Get-CIPPRolePermissions -Times 1 -ParameterFilter { $RoleName -eq 'helpdesk' }
    }

    It 'fails closed for a nonexistent role' {
        Mock Get-CIPPRolePermissions { throw 'Role nope not found.' }
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'superadmin')
        { Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'nope') } |
            Should -Throw '*does not exist*'
    }

    It 'normalizes case and whitespace in the target' {
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'superadmin')
        $Result = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest ' Editor ')
        $Result.Impersonating | Should -Be 'editor'
    }

    It 'writes the audit row once per user+role, again for a different role' {
        $User = & $script:MakeUser @('anonymous', 'authenticated', 'superadmin')
        $null = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'readonly')
        $null = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'readonly')
        Should -Invoke Write-LogMessage -Times 1
        $null = Resolve-CippImpersonation -User $User -Request (& $script:MakeRequest 'editor')
        Should -Invoke Write-LogMessage -Times 2
    }
}
