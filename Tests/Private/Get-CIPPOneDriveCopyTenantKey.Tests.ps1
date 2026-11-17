# Pester tests for Get-CIPPOneDriveCopyTenantKey: OneDriveCopyToUser rows are keyed by the tenant's
# customerId whatever form of the tenant the caller used, and old rows under the raw value stay readable.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-Tenants { param($TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPOneDriveCopyTenantKey.ps1')
    $script:CustomerId = 'c0ffee00-1111-2222-3333-444444444444'
}

Describe 'Get-CIPPOneDriveCopyTenantKey' {
    BeforeEach {
        Mock Get-Tenants {
            if ($TenantFilter -in @('contoso.com', 'contoso.onmicrosoft.com', $script:CustomerId)) {
                [pscustomobject]@{ customerId = $script:CustomerId; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' }
            }
        }
    }

    It 'keys <Given> by the customerId' -ForEach @(
        @{ Given = 'contoso.com' }
        @{ Given = 'Contoso.COM' }
        @{ Given = 'contoso.onmicrosoft.com' }
        @{ Given = 'c0ffee00-1111-2222-3333-444444444444' }
        @{ Given = 'C0FFEE00-1111-2222-3333-444444444444' }
        @{ Given = ' contoso.com ' }
    ) {
        $Keys = Get-CIPPOneDriveCopyTenantKey -TenantFilter $Given
        $Keys.Key | Should -BeExactly $script:CustomerId
        $Keys.ReadKeys[0] | Should -BeExactly $script:CustomerId
    }

    It 'still reads rows written under the raw tenantFilter, after the customerId' {
        (Get-CIPPOneDriveCopyTenantKey -TenantFilter 'Contoso.COM').ReadKeys | Should -Be @($script:CustomerId, 'Contoso.COM')
        (Get-CIPPOneDriveCopyTenantKey -TenantFilter $script:CustomerId).ReadKeys | Should -Be @($script:CustomerId)
    }

    It 'asks Get-Tenants with the lower-cased value, because its table lookups are case-sensitive' {
        $null = Get-CIPPOneDriveCopyTenantKey -TenantFilter 'Contoso.COM'
        Should -Invoke Get-Tenants -Times 1 -Exactly -ParameterFilter { $TenantFilter -ceq 'contoso.com' }
    }

    It 'keys a tenant Get-Tenants does not know by its lower-cased tenantFilter' {
        $Keys = Get-CIPPOneDriveCopyTenantKey -TenantFilter 'Unknown.example'
        $Keys.Key | Should -BeExactly 'unknown.example'
        $Keys.ReadKeys | Should -Be @('unknown.example', 'Unknown.example')
    }

    It 'lets a tenant cache failure through rather than guessing a key' {
        Mock Get-Tenants { throw 'Storage 503' }
        { Get-CIPPOneDriveCopyTenantKey -TenantFilter 'contoso.com' } | Should -Throw '*503*'
    }
}
