BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-Tenants { param([switch]$IncludeErrors, [switch]$IncludeAll, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AuthorisedRequestError.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
}

Describe 'Get-AuthorisedRequestError' {
    BeforeEach {
        $env:TenantID = 'partner-tenant-id'
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $null }
    }
    AfterAll {
        Remove-Item Env:TenantID -ErrorAction SilentlyContinue
    }

    It 'tells an unrestricted caller the tenant is not managed, as a 404' {
        Mock Get-Tenants { }
        $Exception = Get-AuthorisedRequestError -TenantID 'gone.onmicrosoft.com' -Context 'Graph request'
        $Exception.Message | Should -Be "Graph request denied for 'gone.onmicrosoft.com': the tenant is not in CIPP's tenant list."
        Get-CippErrorStatusCode -ErrorRecord $Exception | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'tells an unrestricted caller the tenant is excluded, as a 403' {
        # Only a lookup that includes excluded tenants returns the row, as Get-Tenants does.
        Mock Get-Tenants { }
        Mock Get-Tenants -ParameterFilter { $IncludeAll } { [pscustomobject]@{ customerId = 'x'; Excluded = $true } }
        $Exception = Get-AuthorisedRequestError -TenantID 'excluded.onmicrosoft.com' -Context 'Graph request'
        $Exception.Message | Should -Be "Graph request denied for 'excluded.onmicrosoft.com': the tenant is excluded from CIPP management."
        Get-CippErrorStatusCode -ErrorRecord $Exception | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
    }

    It 'does not tell a restricted caller that a tenant outside their access is excluded' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('tenant-a') }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'x'; Excluded = $true } }
        (Get-AuthorisedRequestError -TenantID 'excluded.onmicrosoft.com' -Context 'Graph request').Message |
            Should -Be "Graph request denied for 'excluded.onmicrosoft.com': the tenant is outside your access."
    }

    It 'tells a restricted caller their own tenant is excluded' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('x') }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'x'; Excluded = $true } }
        (Get-AuthorisedRequestError -TenantID 'excluded.onmicrosoft.com' -Context 'Graph request').Message |
            Should -BeLike '*the tenant is excluded from CIPP management.'
    }

    It 'tells a restricted caller the tenant is outside their access, whether or not it exists, as a 403' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('tenant-a') }
        Mock Get-Tenants { }
        $Exception = Get-AuthorisedRequestError -TenantID 'other.onmicrosoft.com' -Context 'Graph request'
        $Exception.Message | Should -Be "Graph request denied for 'other.onmicrosoft.com': the tenant is outside your access."
        Get-CippErrorStatusCode -ErrorRecord $Exception | Should -Be ([System.Net.HttpStatusCode]::Forbidden)
    }

    It 'tells a restricted caller that a request with no tenant fell back to the partner tenant' {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = @('tenant-a') }
        Mock Get-Tenants { }
        (Get-AuthorisedRequestError -TenantID '' -Context 'Graph request').Message |
            Should -BeLike 'Graph request denied: no tenant was selected, so it ran against the partner tenant*Select one of your tenants*'
    }

    # A non-terminating Write-Error lets the endpoint carry on and return 200 with no data.
    It 'is always thrown, never written as a non-terminating error' {
        $Offenders = foreach ($File in Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter '*.ps1' -File) {
            if (Select-String -LiteralPath $File.FullName -Pattern 'Write-Error\s*\(?\s*\(?Get-AuthorisedRequestError' -Quiet) { $File.Name }
        }
        $Offenders | Should -BeNullOrEmpty
    }
}
