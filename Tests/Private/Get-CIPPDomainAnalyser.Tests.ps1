BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippRequestContext { [pscustomobject]@{ AllowedTenants = $null } }
    function Get-CIPPTable { @{} }
    function Get-Tenants { [pscustomobject]@{ customerId = 'guid-1' } }
    function Get-CIPPAzDataTableEntity { [pscustomobject]@{ TenantGUID = 'guid-1'; DomainAnalyser = '{"Domain":"contoso.com"}' } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDomainAnalyser.ps1')
}

Describe 'Get-CIPPDomainAnalyser' {
    BeforeEach { $script:CIPPDomainAnalyserCache = $null; $script:CIPPDomainAnalyserSweep = $null }

    It 'removes expired results when it caches new ones' {
        $script:CIPPDomainAnalyserCache = @{}
        $Old = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 301
        foreach ($i in 1..300) { $script:CIPPDomainAnalyserCache["tenant$i"] = @{ Results = @([pscustomobject]@{ Domain = "tenant$i.com" }); Timestamp = $Old } }

        (Get-CIPPDomainAnalyser -TenantFilter 'AllTenants').Domain | Should -Be 'contoso.com'

        @($script:CIPPDomainAnalyserCache.Keys) | Should -Be @('AllTenants')
    }
}
