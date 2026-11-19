BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Get-CippAccessScopeVersion { 'v1' }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPRoleIPRanges.ps1')
}

Describe 'Get-CIPPRoleIPRanges' {
    BeforeEach {
        $script:CippRoleIPRangeCache = $null
        $script:Version = 'v1'
        $script:Rows = @{ helpdesk = '["10.0.0.0/24"]'; office = '["192.168.1.1","10.0.0.0/24"]' }
        Mock Get-CippAccessScopeVersion { $script:Version }
        Mock Get-CIPPAzDataTableEntity {
            $Name = $Filter.Substring(11).TrimEnd("'")
            if ($Name -eq 'broken') { throw 'storage down' }
            if ($script:Rows.ContainsKey($Name)) { [PSCustomObject]@{ RowKey = $Name; IPRanges = $script:Rows[$Name] } }
        }
    }

    It 'combines the ranges of every role and allows any address when none has a range' {
        Get-CIPPRoleIPRanges -Roles @('Helpdesk', 'office', 'authenticated') | Should -Be @('10.0.0.0/24', '192.168.1.1')
        Get-CIPPRoleIPRanges -Roles @('authenticated', 'anonymous') | Should -Be @('Any')
    }

    It 'never restricts a superadmin and reads nothing for one' {
        Get-CIPPRoleIPRanges -Roles @('superadmin', 'helpdesk') | Should -Be @('Any')
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'reads each role once, including a role with no range' {
        $First = Get-CIPPRoleIPRanges -Roles @('helpdesk', 'authenticated')
        $Second = Get-CIPPRoleIPRanges -Roles @('helpdesk', 'authenticated')
        $Second | Should -Be $First
        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
    }

    It 'keeps ranges per role, never per caller' {
        Get-CIPPRoleIPRanges -Roles @('helpdesk', 'office') | Should -Be @('10.0.0.0/24', '192.168.1.1')
        Get-CIPPRoleIPRanges -Roles @('helpdesk') | Should -Be @('10.0.0.0/24')
        Get-CIPPRoleIPRanges -Roles @('authenticated') | Should -Be @('Any')
    }

    It 'picks up a changed range once the shared version changes' {
        $null = Get-CIPPRoleIPRanges -Roles @('helpdesk')
        $script:Rows.helpdesk = '["172.16.0.1"]'
        Get-CIPPRoleIPRanges -Roles @('helpdesk') | Should -Be @('10.0.0.0/24')
        $script:Version = 'v2'
        Get-CIPPRoleIPRanges -Roles @('helpdesk') | Should -Be @('172.16.0.1')
    }

    It 'picks up a newly added range once the shared version changes' {
        Get-CIPPRoleIPRanges -Roles @('readonly') | Should -Be @('Any')
        $script:Rows.readonly = '["172.16.0.1"]'
        $script:Version = 'v2'
        Get-CIPPRoleIPRanges -Roles @('readonly') | Should -Be @('172.16.0.1')
    }

    It 'reads again after the entry expires' {
        $null = Get-CIPPRoleIPRanges -Roles @('helpdesk')
        foreach ($Entry in $script:CippRoleIPRangeCache.Values) { $Entry.Expires = [datetime]::UtcNow.AddSeconds(-1) }
        $null = Get-CIPPRoleIPRanges -Roles @('helpdesk')
        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
    }

    It 'does not keep a failed read' {
        Get-CIPPRoleIPRanges -Roles @('broken', 'helpdesk') 6>$null | Should -Be @('10.0.0.0/24')
        $null = Get-CIPPRoleIPRanges -Roles @('broken') 6>$null
        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly -ParameterFilter { $Filter -eq "RowKey eq 'broken'" }
    }
}
