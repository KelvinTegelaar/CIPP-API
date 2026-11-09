# Get-AuthorisedRequest runs before every Graph and Exchange call. It remembers a tenant it allowed for the rest of
# the invocation, and nothing else: refusals are re-checked, a new request starts empty and a scope change starts over.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AuthorisedRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Initialize-CippRequestContext.ps1')
}

Describe 'Get-AuthorisedRequest invocation memo' {
    BeforeEach {
        Initialize-CippRequestContext
        Mock Get-Tenants {
            switch ($TenantFilter) {
                'contoso.com' { [pscustomobject]@{ defaultDomainName = 'contoso.com'; Excluded = $false } }
                'excluded.com' { [pscustomobject]@{ defaultDomainName = 'excluded.com'; Excluded = $true } }
            }
        }
    }

    It 'looks a tenant up once per invocation' {
        Get-AuthorisedRequest -TenantID 'contoso.com' | Should -BeTrue
        Get-AuthorisedRequest -TenantID 'CONTOSO.com' | Should -BeTrue

        Should -Invoke Get-Tenants -Times 1 -Exactly
    }

    It 'checks a refused tenant again every time' {
        Get-AuthorisedRequest -TenantID 'unknown.com' | Should -BeFalse
        Get-AuthorisedRequest -TenantID 'excluded.com' | Should -BeFalse
        Get-AuthorisedRequest -TenantID 'unknown.com' | Should -BeFalse

        Should -Invoke Get-Tenants -Times 3 -Exactly
    }

    It 'starts over when the tenant scope changes' {
        $null = Get-AuthorisedRequest -TenantID 'contoso.com'
        $script:CippAllowedTenantsStorage.Value = @('some-customer-id')
        $null = Get-AuthorisedRequest -TenantID 'contoso.com'

        Should -Invoke Get-Tenants -Times 2 -Exactly
    }

    It 'is cleared for the next request' {
        $null = Get-AuthorisedRequest -TenantID 'contoso.com'
        Initialize-CippRequestContext
        $null = Get-AuthorisedRequest -TenantID 'contoso.com'

        Should -Invoke Get-Tenants -Times 2 -Exactly
    }
}
