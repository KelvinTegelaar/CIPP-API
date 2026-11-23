BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/TenantGroups/Get-CIPPTenantGroupVariables.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/TenantGroups/Merge-CIPPListVariableValue.ps1')
}

Describe 'Get-CIPPTenantGroupVariables' {
    BeforeEach {
        $script:VariableRows = @(
            [pscustomobject]@{ PartitionKey = 'group:g1'; RowKey = 'onedrive'; Value = 'allow'; VariableType = 'string' }
            [pscustomobject]@{ PartitionKey = 'group:g2'; RowKey = 'onedrive'; Value = 'allow'; VariableType = 'string' }
            [pscustomobject]@{ PartitionKey = 'group:g1'; RowKey = 'aiblock'; Value = 'true'; VariableType = 'boolean' }
            [pscustomobject]@{ PartitionKey = 'group:g2'; RowKey = 'aiblock'; Value = 'false'; VariableType = 'boolean' }
            [pscustomobject]@{ PartitionKey = 'group:g3'; RowKey = 'notmine'; Value = 'x'; VariableType = 'string' }
            [pscustomobject]@{ PartitionKey = 'group:deleted'; RowKey = 'orphan'; Value = 'x'; VariableType = 'string' }
        )
        $script:Members = @('g1', 'g2', 'deleted')
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            switch ($TableName) {
                'CippReplacemap' { $script:VariableRows }
                'TenantGroupMembers' { foreach ($Id in $script:Members) { [pscustomobject]@{ GroupId = $Id; customerId = 'tenant-1' } } }
                'TenantGroups' {
                    [pscustomobject]@{ RowKey = 'g1'; Name = 'Allow OneDrive' }
                    [pscustomobject]@{ RowKey = 'g2'; Name = 'Finance' }
                    [pscustomobject]@{ RowKey = 'g3'; Name = 'Other' }
                }
            }
        }
    }

    It 'returns a value the tenant groups agree on, with every group that sets it' {
        $Result = Get-CIPPTenantGroupVariables -CustomerId 'tenant-1'
        $Result['onedrive'].Value | Should -Be 'allow'
        $Result['onedrive'].Conflict | Should -BeFalse
        @($Result['onedrive'].Groups) | Should -Be @('Allow OneDrive', 'Finance')
    }

    It 'flags a name the tenant groups disagree on' {
        (Get-CIPPTenantGroupVariables -CustomerId 'tenant-1')['aiblock'].Conflict | Should -BeTrue
    }

    It 'combines lists that every group joins instead of flagging a conflict' {
        $script:VariableRows += @(
            [pscustomobject]@{ PartitionKey = 'group:g1'; RowKey = 'ranges'; Value = '["10.0.0.0/8","172.16.0.0/12"]'; VariableType = 'list'; JoinInherited = $true }
            [pscustomobject]@{ PartitionKey = 'group:g2'; RowKey = 'ranges'; Value = '["172.16.0.0/12","203.0.113.0/24"]'; VariableType = 'list'; JoinInherited = $true }
        )
        $Result = (Get-CIPPTenantGroupVariables -CustomerId 'tenant-1')['ranges']
        $Result.Conflict | Should -BeFalse
        $Result.JoinInherited | Should -BeTrue
        $Result.Value | Should -Be '["10.0.0.0/8","172.16.0.0/12","203.0.113.0/24"]'
    }

    It 'flags lists that differ when a group replaces rather than joins' {
        $script:VariableRows += @(
            [pscustomobject]@{ PartitionKey = 'group:g1'; RowKey = 'ranges'; Value = '["10.0.0.0/8"]'; VariableType = 'list'; JoinInherited = $true }
            [pscustomobject]@{ PartitionKey = 'group:g2'; RowKey = 'ranges'; Value = '["203.0.113.0/24"]'; VariableType = 'list' }
        )
        (Get-CIPPTenantGroupVariables -CustomerId 'tenant-1')['ranges'].Conflict | Should -BeTrue
    }

    It 'ignores groups the tenant is not in and groups that no longer exist' {
        $Result = Get-CIPPTenantGroupVariables -CustomerId 'tenant-1'
        $Result.ContainsKey('notmine') | Should -BeFalse
        $Result.ContainsKey('orphan') | Should -BeFalse
    }

    It 'skips the membership read when no group has variables' {
        $script:VariableRows = @()
        (Get-CIPPTenantGroupVariables -CustomerId 'tenant-1').Count | Should -Be 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
