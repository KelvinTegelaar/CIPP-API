BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AuthorisedRequestError.ps1')
}

Describe 'Get-AuthorisedRequestError' {
    BeforeEach {
        $env:TenantID = 'partner-tenant-id'
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $null }
    }
    AfterAll {
        Remove-Item Env:TenantID -ErrorAction SilentlyContinue
    }

    It 'tells an unrestricted caller the tenant is not managed' {
        Mock Get-Tenants { }
        Get-AuthorisedRequestError -TenantID 'gone.onmicrosoft.com' -Context 'Graph request' |
            Should -Be "Graph request denied for 'gone.onmicrosoft.com': the tenant is not in CIPP's tenant list."
    }

    It 'tells an unrestricted caller the tenant is excluded' {
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'x'; Excluded = $true } }
        Get-AuthorisedRequestError -TenantID 'excluded.onmicrosoft.com' -Context 'Graph request' |
            Should -Be "Graph request denied for 'excluded.onmicrosoft.com': the tenant is excluded from CIPP management."
    }

    It 'tells a restricted caller the tenant is outside their access, whether or not it exists' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('tenant-a') }
        Mock Get-Tenants { }
        Get-AuthorisedRequestError -TenantID 'other.onmicrosoft.com' -Context 'Graph request' |
            Should -Be "Graph request denied for 'other.onmicrosoft.com': the tenant is outside your access."
    }

    It 'tells a restricted caller that a request with no tenant fell back to the partner tenant' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('tenant-a') }
        Mock Get-Tenants { }
        Get-AuthorisedRequestError -TenantID '' -Context 'Graph request' |
            Should -BeLike 'Graph request denied: no tenant was selected, so it ran against the partner tenant*Select one of your tenants*'
    }
}
