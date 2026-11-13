BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Get-TenantGroups.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/TenantGroups/Expand-CIPPTenantGroups.ps1')
}

Describe 'Expand-CIPPTenantGroups' {
    BeforeEach {
        $script:TenantGroupsCache = $null
        $script:TenantGroupsResultCache = $null
        $script:CippAllowedGroupsStorage = $null
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'TenantGroups') {
                [pscustomobject]@{ RowKey = 'g1'; Name = 'One' }
                [pscustomobject]@{ RowKey = 'g2'; Name = 'Two' }
            } else {
                [pscustomobject]@{ GroupId = 'g1'; customerId = 't1' }
                [pscustomobject]@{ GroupId = 'g2'; customerId = 't2' }
            }
        }
        Mock Get-Tenants {
            [pscustomobject]@{ customerId = 't1'; displayName = 'T1'; defaultDomainName = 't1.example' }
            [pscustomobject]@{ customerId = 't2'; displayName = 'T2'; defaultDomainName = 't2.example' }
        }
    }

    It 'expands a group to its own members' {
        @(Expand-CIPPTenantGroups -TenantFilter @([pscustomobject]@{ type = 'Group'; value = 'g1' })).value | Should -Be @('t1.example')
    }

    It 'passes a tenant selector through' {
        @(Expand-CIPPTenantGroups -TenantFilter @([pscustomobject]@{ type = 'Tenant'; value = 't2.example' })).value | Should -Be @('t2.example')
    }

    It 'expands a group selector whose value is <Case> to nothing' -ForEach @(
        @{ Case = 'empty'; Selector = [pscustomobject]@{ type = 'Group'; value = '' } }
        @{ Case = 'whitespace'; Selector = [pscustomobject]@{ type = 'Group'; value = ' ' } }
        @{ Case = 'missing'; Selector = [pscustomobject]@{ type = 'Group' } }
        @{ Case = 'an empty list'; Selector = [pscustomobject]@{ type = 'Group'; value = @() } }
    ) {
        Expand-CIPPTenantGroups -TenantFilter @($Selector) | Should -BeNullOrEmpty
    }

    It 'keeps the other entries when one group selector is empty' {
        $Selection = @(
            [pscustomobject]@{ type = 'Group'; value = '' }
            [pscustomobject]@{ type = 'Tenant'; value = 't2.example' }
        )
        @(Expand-CIPPTenantGroups -TenantFilter $Selection).value | Should -Be @('t2.example')
    }
}
