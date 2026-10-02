# Pester tests for Get-CIPPDbItem's allTenants read and Get-CIPPMailboxRulesReport built on it.
# A tenant-restricted caller must only read its own tenants' partitions; an unrestricted one
# reads the table once.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function Get-CippTable { param($tablename) @{ Context = 'ctx' } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    $script:CippAllowedTenantsStorage = [System.Threading.AsyncLocal[object]]::new()

    . (Join-Path $Public 'Get-CIPPDbItem.ps1')
    . (Join-Path $Public 'Get-CIPPMailboxRulesReport.ps1')

    $script:TenantA = [pscustomobject]@{ customerId = 'a'; defaultDomainName = 'a.com' }
    $script:TenantB = [pscustomobject]@{ customerId = 'b'; defaultDomainName = 'b.com' }

    $T1 = [datetimeoffset]'2026-09-29T01:00:00Z'
    $T2 = [datetimeoffset]'2026-09-29T02:00:00Z'
    $script:Rows = @(
        [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'MailboxRules-1'; Timestamp = $T1; Data = '{"Name":"a1"}' }
        [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'MailboxRules-2'; Timestamp = $T2; Data = '{"Name":"a2"}' }
        [pscustomobject]@{ PartitionKey = 'b.com'; RowKey = 'MailboxRules-1'; Timestamp = $T1; Data = '{"Name":"b1","Tenant":"stored.com"}' }
        [pscustomobject]@{ PartitionKey = 'gone.com'; RowKey = 'MailboxRules-1'; Timestamp = $T1; Data = '{"Name":"orphan"}' }
    )
}

Describe 'Get-CIPPDbItem allTenants' {
    BeforeEach {
        $script:Filters = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPAzDataTableEntity {
            $script:Filters.Add($Filter)
            if ($Filter -match "PartitionKey eq '([^']+)'") { $P = $Matches[1]; $script:Rows | Where-Object PartitionKey -EQ $P } else { $script:Rows }
        }
    }

    It 'reads the whole table once for an unrestricted caller' {
        $script:CippAllowedTenantsStorage.Value = $null
        $Result = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules'
        $script:Filters.Count | Should -Be 1
        $script:Filters[0] | Should -Not -Match 'PartitionKey'
        @($Result).Count | Should -Be 4
    }

    It 'reads only the allowed partitions for a scoped caller' {
        Mock Get-Tenants { @($script:TenantA) }
        $script:CippAllowedTenantsStorage.Value = @('a')
        $Result = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules'
        $script:Filters | Should -HaveCount 1
        $script:Filters[0] | Should -BeLike "PartitionKey eq 'a.com' and RowKey ge 'MailboxRules-'*"
        @($Result.PartitionKey | Sort-Object -Unique) | Should -Be @('a.com')
    }

    It 'reads nothing for a scoped caller with no tenants' {
        Mock Get-Tenants { @() }
        $script:CippAllowedTenantsStorage.Value = @('none')
        $Result = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules'
        $script:Filters.Count | Should -Be 0
        @($Result).Count | Should -Be 0
    }

    It 'keeps -CountsOnly scoped with the projected properties' {
        Mock Get-Tenants { @($script:TenantA, $script:TenantB) }
        $script:CippAllowedTenantsStorage.Value = @('a', 'b')
        $null = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules' -CountsOnly
        $script:Filters | Should -Be @("PartitionKey eq 'a.com' and RowKey eq 'MailboxRules-Count'", "PartitionKey eq 'b.com' and RowKey eq 'MailboxRules-Count'")
        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly -ParameterFilter { $Property -contains 'DataCount' }
    }

    It '-ByTenant groups data rows by managed tenant, without count rows' {
        $script:CippAllowedTenantsStorage.Value = $null
        Mock Get-Tenants { @($script:TenantA, $script:TenantB) }
        Mock Get-CIPPAzDataTableEntity { $script:Rows; [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'MailboxRules-Count'; DataCount = 2 } }
        $Result = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules' -ByTenant
        @($Result.Keys) | Should -Be @('a.com', 'b.com')
        $Result['a.com'].RowKey | Should -Be @('MailboxRules-1', 'MailboxRules-2')
        $Result['b.com'].Count | Should -Be 1
    }

    It '-ByTenant for a scoped caller reads and returns only its tenants' {
        Mock Get-Tenants { @($script:TenantB) }
        $script:CippAllowedTenantsStorage.Value = @('b')
        $Result = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MailboxRules' -ByTenant
        @($Result.Keys) | Should -Be @('b.com')
        $script:Filters | Should -HaveCount 1
    }

    AfterAll { $script:CippAllowedTenantsStorage.Value = $null }
}

Describe 'Get-CIPPMailboxRulesReport' {
    BeforeEach {
        $script:CippAllowedTenantsStorage.Value = $null
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "PartitionKey eq '([^']+)'") { $P = $Matches[1]; $script:Rows | Where-Object PartitionKey -EQ $P } else { $script:Rows }
        }
        Mock Get-Tenants {
            if ($TenantFilter) { @($script:TenantA, $script:TenantB) | Where-Object defaultDomainName -EQ $TenantFilter } else { @($script:TenantA, $script:TenantB) }
        }
    }

    It 'reads AllTenants once, drops unmanaged tenants and stamps each tenant''s latest timestamp' {
        $Result = Get-CIPPMailboxRulesReport -TenantFilter 'AllTenants'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
        @($Result.Name | Sort-Object) | Should -Be @('a1', 'a2', 'b1')
        ($Result | Where-Object Name -EQ 'a1').CacheTimestamp | Should -Be ([datetimeoffset]'2026-09-29T02:00:00Z')
        ($Result | Where-Object Name -EQ 'b1').CacheTimestamp | Should -Be ([datetimeoffset]'2026-09-29T01:00:00Z')
        ($Result | Where-Object Name -EQ 'a1').Tenant | Should -Be 'a.com'
        ($Result | Where-Object Name -EQ 'b1').Tenant | Should -Be 'stored.com'
    }

    It 'returns a single tenant''s rules' {
        $Result = Get-CIPPMailboxRulesReport -TenantFilter 'b.com'
        @($Result.Name) | Should -Be @('b1')
    }

    It 'throws when a single tenant has no cached rules' {
        Mock Get-CIPPAzDataTableEntity { }
        { Get-CIPPMailboxRulesReport -TenantFilter 'a.com' } | Should -Throw '*No mailbox rules data*'
    }

    It 'returns nothing rather than throwing for AllTenants with no cached rules' {
        Mock Get-CIPPAzDataTableEntity { }
        @(Get-CIPPMailboxRulesReport -TenantFilter 'AllTenants').Count | Should -Be 0
    }
}
