BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Get-TenantGroups.ps1')
}

Describe 'Get-TenantGroups request group scope' {
    BeforeEach {
        $script:TenantGroupsCache = $null
        $script:TenantGroupsResultCache = $null
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'TenantGroups') {
                [pscustomobject]@{ RowKey = 'g1'; Name = 'One' }
                [pscustomobject]@{ RowKey = 'g2'; Name = 'Two' }
            } else {
                [pscustomobject]@{ GroupId = 'g1'; customerId = 't1' }
            }
        }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 't1'; displayName = 'T1'; defaultDomainName = 't1.example' } }
    }
    AfterAll { $script:CippAllowedGroupsStorage = $null }

    It '<Caller> sees <Expect>' -ForEach @(
        @{ Caller = 'an unscoped caller'; Scope = $null; Expect = @('One', 'Two') }
        @{ Caller = 'a caller granted g1'; Scope = @('g1'); Expect = @('One') }
        @{ Caller = 'a caller granted no groups'; Scope = @(); Expect = @() }
    ) {
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = $Scope }
        @(Get-TenantGroups).Name | Should -Be $Expect
    }

    It 'does not answer a group outside the scope from a result cached under a wider scope' {
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = $null }
        (Get-TenantGroups -GroupId 'g2').Name | Should -Be 'Two'
        $script:CippAllowedGroupsStorage = [pscustomobject]@{ Value = @('g1') }
        Get-TenantGroups -GroupId 'g2' | Should -BeNullOrEmpty
    }
}
