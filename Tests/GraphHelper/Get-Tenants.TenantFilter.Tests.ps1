# Get-Tenants narrows the cached tenant list in memory with a literal filter script block. It used to
# build that filter with [scriptblock]::Create and the tenant id/domain in the text, adding a PowerShell
# script block cache entry per tenant; past 1024 entries the cache empties, and the next runspace to open
# re-parses every module.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData, $headers, $level) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }

    $script:SourcePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-Tenants.ps1'
    . $script:SourcePath

    $script:Tenants = @(
        [PSCustomObject]@{ RowKey = '11111111-1111-1111-1111-111111111111'; customerId = '11111111-1111-1111-1111-111111111111'; displayName = 'Contoso'; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' }
        [PSCustomObject]@{ RowKey = '22222222-2222-2222-2222-222222222222'; customerId = '22222222-2222-2222-2222-222222222222'; displayName = 'Fabrikam'; defaultDomainName = 'fabrikam.com'; initialDomainName = 'fabrikam.onmicrosoft.com' }
        [PSCustomObject]@{ RowKey = '33333333-3333-3333-3333-333333333333'; customerId = '33333333-3333-3333-3333-333333333333'; displayName = "O'Brien"; defaultDomainName = "o'brien.com"; initialDomainName = 'obrien.onmicrosoft.com' }
    )
}

Describe 'Get-Tenants -TenantFilter' {
    BeforeEach {
        Mock Get-CippTable { @{} }
        Mock Write-LogMessage {}
        Mock ConvertTo-CIPPODataFilterValue { $Value -replace "'", "''" }
        # The table read ignores the OData filter here, so only the in-memory filter narrows the list.
        Mock Get-CIPPAzDataTableEntity { $script:Tenants }
    }

    It 'matches <Filter> to <Expected>' -ForEach @(
        @{ Filter = '22222222-2222-2222-2222-222222222222'; Expected = 'Fabrikam' }
        @{ Filter = 'contoso.com'; Expected = 'Contoso' }
        @{ Filter = 'FABRIKAM.onmicrosoft.com'; Expected = 'Fabrikam' }
        @{ Filter = "o'brien.com"; Expected = "O'Brien" }
    ) {
        $Result = @(Get-Tenants -TenantFilter $Filter)

        $Result.Count | Should -Be 1
        $Result[0].displayName | Should -Be $Expected
    }

    It 'returns every tenant without a filter' {
        @(Get-Tenants).Count | Should -Be 3
    }

    It 'never builds a script block from text' {
        Get-Content -Raw $script:SourcePath | Should -Not -Match '\[scriptblock\]::Create'
    }
}
