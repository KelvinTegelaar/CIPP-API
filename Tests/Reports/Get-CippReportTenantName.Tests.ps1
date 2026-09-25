# Pester tests for the branding's tenantLabel: which of the tenant's names a report prints.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippReportTenantName.ps1' | Select-Object -First 1 -ExpandProperty FullName)

    $script:Tenant = [PSCustomObject]@{ displayName = 'Contoso (alias)'; defaultDomainName = 'contoso.onmicrosoft.com'; customerId = 'guid' }
    $script:Settings = @{ tenantLabel = 'alias' }
    $script:Presets = @{}
    $script:GraphCalls = 0
    function Get-Tenants { param($TenantFilter) $script:Tenant }
    function Get-CIPPBrandingSettings { $script:Settings }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) $script:Presets[$Id] }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) $script:GraphCalls++; [PSCustomObject]@{ displayName = 'Contoso Ltd' } }
}

Describe 'Get-CippReportTenantName' {
    BeforeEach { $script:GraphCalls = 0 }

    It 'prints the name CIPP shows by default, without touching Graph' {
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' | Should -Be 'Contoso (alias)'
        $script:GraphCalls | Should -Be 0
    }

    It 'prints the default domain when the branding asks for it' {
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -Branding @{ tenantLabel = 'domain' } | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'prints the organisation name from Graph when the branding asks for it, since the cache holds the alias' {
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -Branding @{ tenantLabel = 'name' } | Should -Be 'Contoso Ltd'
        $script:GraphCalls | Should -Be 1
    }

    It 'lets a preset decide over the global setting' {
        $script:Presets['p1'] = @{ tenantLabel = 'domain' }
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -BrandingPresetId 'p1' | Should -Be 'contoso.onmicrosoft.com'
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -BrandingPresetId 'missing' | Should -Be 'Contoso (alias)'
    }

    It 'falls back to the shown name when Graph cannot answer, and to the filter when nothing is cached' {
        function New-GraphGetRequest { throw 'no access' }
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -Branding @{ tenantLabel = 'name' } | Should -Be 'Contoso (alias)'
        function Get-Tenants { param($TenantFilter) $null }
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -Branding @{ tenantLabel = 'domain' } | Should -Be 'contoso.onmicrosoft.com'
        Get-CippReportTenantName -TenantFilter 'contoso.onmicrosoft.com' -Branding @{ tenantLabel = 'alias' } | Should -Be 'contoso.onmicrosoft.com'
    }
}
