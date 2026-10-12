# The caller's permissions are resolved once per request into a CIPPCore request-context slot that
# Initialize-CippRequestContext resets, so a worker reused for the next request never inherits them.
# Loaded as the real module and called from another one, the way CIPPHTTP's ExecMcp reaches it.

BeforeAll {
    $script:ModulesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
    Import-Module (Join-Path $script:ModulesRoot 'CIPPCore/CIPPCore.psd1') -Force 3>$null
    $script:Core = Get-Module CIPPCore

    New-Module -Name PermissionProbeHttp -ScriptBlock {
        function Invoke-PermissionProbe { , (Get-CippRequestAllowedPermissions) }
        Export-ModuleMember -Function Invoke-PermissionProbe
    } | Import-Module

    # What New-CippCoreRequest + Test-CIPPAccess leave behind for a request, run inside CIPPCore
    function Enter-ProbeRequest($Roles) {
        & $script:Core {
            param($R)
            Initialize-CippRequestContext
            $script:CippAccessUserContext = if ($null -ne $R) { [pscustomobject]@{ User = 'probe'; Roles = @($R) } } else { $null }
        } $Roles
    }
}

AfterAll {
    Remove-Module PermissionProbeHttp, CIPPCore -Force -ErrorAction SilentlyContinue
}

Describe 'Get-CippRequestAllowedPermissions' {
    BeforeEach {
        Mock -ModuleName CIPPCore Get-CippAllowedPermissions { @("$($UserRoles[0]).Perm.Read") }
    }

    It 'resolves the permissions of the roles the access check found' {
        Enter-ProbeRequest @('readonly')
        Invoke-PermissionProbe | Should -Be @('readonly.Perm.Read')
        Should -Invoke -ModuleName CIPPCore Get-CippAllowedPermissions -Times 1 -Exactly -ParameterFilter { $UserRoles -contains 'readonly' }
    }

    It 'resolves once per request' {
        Enter-ProbeRequest @('readonly')
        $null = Invoke-PermissionProbe
        $null = Invoke-PermissionProbe
        Should -Invoke -ModuleName CIPPCore Get-CippAllowedPermissions -Times 1 -Exactly
    }

    It 'does not carry one caller''s permissions into the next request' {
        Enter-ProbeRequest @('superadmin')
        $null = Invoke-PermissionProbe
        Enter-ProbeRequest @('readonly')
        Invoke-PermissionProbe | Should -Be @('readonly.Perm.Read')
    }

    It 'returns an empty list, not $null, for a caller whose roles grant nothing' {
        Enter-ProbeRequest @()
        $Result = Invoke-PermissionProbe
        $null -eq $Result | Should -BeFalse
        @($Result).Count | Should -Be 0
        Should -Invoke -ModuleName CIPPCore Get-CippAllowedPermissions -Times 0 -Exactly
    }

    It 'returns $null outside an authenticated request' {
        Enter-ProbeRequest $null
        Invoke-PermissionProbe | Should -BeNullOrEmpty
        $null -eq (Invoke-PermissionProbe) | Should -BeTrue
    }
}
