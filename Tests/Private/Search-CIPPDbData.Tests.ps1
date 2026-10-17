# Search-CIPPDbData across all tenants reads one managed tenant's partition at a time, in key order,
# and stops reading once -Limit is reached, instead of loading every tenant's rows in one table scan.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function Get-CippTable { param($tablename) @{ Context = 'ctx' } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()

    . (Join-Path $Public 'Get-CIPPDbItem.ps1')
    . (Join-Path $Public 'Search-CIPPDbData.ps1')

    $script:Rows = @(
        [pscustomobject]@{ PartitionKey = 'b.com'; RowKey = 'ServicePrincipals-1'; Data = '{"id":"1","displayName":"Microsoft Teams"}' }
        [pscustomobject]@{ PartitionKey = 'b.com'; RowKey = 'ServicePrincipals-Count'; DataCount = 1 }
        [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'ServicePrincipals-1'; Data = '{"id":"1","displayName":"Microsoft Teams"}' }
        [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'ServicePrincipals-2'; Data = '{"id":"2","displayName":"C++ (Build) Tools"}' }
        [pscustomobject]@{ PartitionKey = 'gone.com'; RowKey = 'ServicePrincipals-1'; Data = '{"id":"1","displayName":"Microsoft Teams"}' }
    )
}

Describe 'Search-CIPPDbData all tenants' {
    BeforeEach {
        $script:CippAllowedTenantsStorage.Value = $null
        $script:Filters = [System.Collections.Generic.List[string]]::new()
        Mock Get-Tenants { @([pscustomobject]@{ defaultDomainName = 'b.com' }, [pscustomobject]@{ defaultDomainName = 'a.com' }) }
        Mock Get-CIPPAzDataTableEntity {
            $script:Filters.Add($Filter)
            if ($Filter -match "PartitionKey eq '([^']+)'") { $P = $Matches[1]; $script:Rows | Where-Object PartitionKey -EQ $P } else { $script:Rows }
        }
    }

    It 'reads each managed tenant''s partition in key order, never the whole table' {
        $Result = Search-CIPPDbData -TenantFilter 'allTenants' -SearchTerms 'teams' -Types 'ServicePrincipals'
        $script:Filters | Should -HaveCount 2
        $script:Filters[0] | Should -BeLike "PartitionKey eq 'a.com' and *"
        $script:Filters[1] | Should -BeLike "PartitionKey eq 'b.com' and *"
        @($Result.Tenant) | Should -Be @('a.com', 'b.com')
    }

    It 'stops reading tenants once the limit is reached' {
        $Result = Search-CIPPDbData -SearchTerms 'teams' -Types 'ServicePrincipals' -Limit 1
        $script:Filters | Should -HaveCount 1
        @($Result.Tenant) | Should -Be @('a.com')
    }

    It 'matches terms as case-insensitive literal text and skips count rows' {
        $Result = Search-CIPPDbData -SearchTerms 'c++ (build)' -Types 'ServicePrincipals' -Properties 'id', 'displayName'
        @($Result.RowKey) | Should -Be @('ServicePrincipals-2')
        $Result.Data.displayName | Should -Be 'C++ (Build) Tools'
    }

    It 'still searches an explicit tenant list one tenant at a time' {
        Mock Get-Tenants { if ($TenantFilter) { [pscustomobject]@{ defaultDomainName = $TenantFilter } } }
        $Result = Search-CIPPDbData -TenantFilter 'b.com' -SearchTerms 'teams' -Types 'ServicePrincipals'
        $script:Filters | Should -HaveCount 1
        @($Result.Tenant) | Should -Be @('b.com')
    }
}
