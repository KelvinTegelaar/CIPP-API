# Pester tests for Select-CippAllowedTenantData
# Verifies that cached rows are narrowed to the caller's allowed tenants when a tenant-restricted
# scope is in force, and passed through untouched when the caller is unrestricted. This is the
# guard that stops a tenant-restricted role from reading every tenant's cached data via
# tenantFilter=AllTenants on the direct cache-reader endpoints.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Select-CippAllowedTenantData.ps1'

    # Minimal stub so Mock has a command to replace
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }

    # The function reads $script:CippAllowedTenantsStorage. Dot-sourcing puts it in this script
    # scope, so create the same AsyncLocal slot here and drive it per-test.
    $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()

    . $FunctionPath

    # Two allowed tenants (tenantA/tenantB) and one that must never leak (tenantC).
    $script:TenantA = [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111'; defaultDomainName = 'tenanta.onmicrosoft.com'; initialDomainName = 'tenanta.onmicrosoft.com' }
    $script:TenantB = [pscustomobject]@{ customerId = '22222222-2222-2222-2222-222222222222'; defaultDomainName = 'tenantb.onmicrosoft.com'; initialDomainName = 'tenantb.onmicrosoft.com' }

    # Cache rows carry Tenant = defaultDomainName (the shape written by the queue functions).
    $script:MixedRows = @(
        [pscustomobject]@{ Tenant = 'tenanta.onmicrosoft.com'; Data = 'A' }
        [pscustomobject]@{ Tenant = 'tenantb.onmicrosoft.com'; Data = 'B' }
        [pscustomobject]@{ Tenant = 'tenantc.onmicrosoft.com'; Data = 'C-should-not-leak' }
    )
}

Describe 'Select-CippAllowedTenantData' {

    Context 'Restricted caller (scope set to tenantA + tenantB)' {
        BeforeEach {
            # Get-Tenants is already narrowed to the caller's scope by the storage filter, so it
            # only ever returns the allowed tenants.
            Mock -CommandName Get-Tenants -MockWith { @($script:TenantA, $script:TenantB) }
            $script:CippAllowedTenantsStorage.Value = @($script:TenantA.customerId, $script:TenantB.customerId)
        }

        It 'returns only rows for allowed tenants' {
            $Result = $script:MixedRows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            @($Result).Count | Should -Be 2
            $Result.Data | Should -Contain 'A'
            $Result.Data | Should -Contain 'B'
        }

        It 'never returns a row for a tenant outside the scope' {
            $Result = $script:MixedRows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            $Result.Data | Should -Not -Contain 'C-should-not-leak'
        }

        It 'matches rows by customerId as well as domain name' {
            $Rows = @(
                [pscustomobject]@{ TenantId = $script:TenantA.customerId; Data = 'A' }
                [pscustomobject]@{ TenantId = '33333333-3333-3333-3333-333333333333'; Data = 'C-should-not-leak' }
            )
            $Result = $Rows | Select-CippAllowedTenantData -TenantProperty 'TenantId'
            @($Result).Count | Should -Be 1
            $Result.Data | Should -Be 'A'
        }

        It 'matches case-insensitively' {
            $Rows = @([pscustomobject]@{ Tenant = 'TENANTA.ONMICROSOFT.COM'; Data = 'A' })
            $Result = $Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            @($Result).Count | Should -Be 1
        }

        It 'drops partner/system CIPP rows unless -AllowPartner is set' {
            $Rows = @([pscustomobject]@{ Tenant = 'CIPP'; Data = 'system' })
            (@($Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant')).Count | Should -Be 0
            (@($Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant' -AllowPartner)).Count | Should -Be 1
        }
    }

    Context 'Unrestricted caller (no scope)' {
        BeforeEach {
            Mock -CommandName Get-Tenants -MockWith { throw 'Get-Tenants must not be called for an unrestricted caller' }
            $script:CippAllowedTenantsStorage.Value = $null
        }

        It 'passes every row through unchanged' {
            $Result = $script:MixedRows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            @($Result).Count | Should -Be 3
        }

        It 'does not call Get-Tenants (zero overhead)' {
            $null = $script:MixedRows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            Should -Invoke -CommandName Get-Tenants -Times 0 -Exactly
        }

        It 'does not treat an explicit empty scope as unrestricted' {
            Mock -CommandName Get-Tenants -MockWith { throw 'Get-Tenants must not be called when scope is empty' }
            $script:CippAllowedTenantsStorage.Value = @()
            $Result = $script:MixedRows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            @($Result).Count | Should -Be 0
        }
    }

    Context 'Restricted caller with zero effective tenants' {
        BeforeEach {
            Mock -CommandName Get-Tenants -MockWith { throw 'Get-Tenants must not be called when scope is empty' }
            $script:CippAllowedTenantsStorage.Value = @()
        }

        It 'returns no rows from a non-empty cache input' {
            $Result = $script:MixedRows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
            @($Result).Count | Should -Be 0
        }
    }
}
