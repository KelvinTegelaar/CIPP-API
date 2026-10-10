BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    foreach ($File in @('Authentication/ConvertTo-CIPPIPRange.ps1', 'Authentication/Test-IpInRange.ps1', 'Authentication/Get-CIPPIPAllowBlockList.ps1', 'Authentication/Resolve-CIPPIPAllowBlockList.ps1', 'BEC/ConvertTo-CIPPBecHostAddress.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
}

Describe 'ConvertTo-CIPPIPRange' {
    It 'normalises addresses and ranges and drops a single-host prefix' {
        ConvertTo-CIPPIPRange -Value ' 203.0.113.10 ' | Should -Be '203.0.113.10'
        ConvertTo-CIPPIPRange -Value '203.0.113.0/24' | Should -Be '203.0.113.0/24'
        ConvertTo-CIPPIPRange -Value '203.0.113.10/32' | Should -Be '203.0.113.10'
        ConvertTo-CIPPIPRange -Value '[2001:DB8::1]' | Should -Be '2001:db8::1'
        ConvertTo-CIPPIPRange -Value '2001:db8::/48' | Should -Be '2001:db8::/48'
    }

    It 'rejects anything that is not an address or a valid prefix' {
        { ConvertTo-CIPPIPRange -Value 'example.com' } | Should -Throw
        { ConvertTo-CIPPIPRange -Value '203.0.113.0/33' } | Should -Throw
        { ConvertTo-CIPPIPRange -Value '2001:db8::/129' } | Should -Throw
        { ConvertTo-CIPPIPRange -Value '12345' } | Should -Throw -Because 'a bare integer parses as an IPv4 address in .NET'
        { ConvertTo-CIPPIPRange -Value '' } | Should -Throw
    }
}

Describe 'Get-CIPPIPAllowBlockList' {
    It 'reads active tenant and AllTenants rows, including legacy key-only rows and underscore-keyed ranges' {
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = '203.0.113.0_24'; Range = '203.0.113.0/24'; state = 'Trusted'; Note = 'office' }
                [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = '198.51.100.7'; state = 'Blocked' }
                [pscustomobject]@{ PartitionKey = 'AllTenants'; RowKey = 'garbage'; state = 'Blocked' }
            )
        }
        $List = Get-CIPPIPAllowBlockList -TenantFilter 'contoso.com'
        $List.Count | Should -Be 2 -Because 'an unparseable row is skipped, not fatal'
        ($List | Where-Object Range -EQ '203.0.113.0/24').Prefix | Should -Be 24
        ($List | Where-Object Range -EQ '198.51.100.7').Scope | Should -Be 'AllTenants'
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -match "PartitionKey eq 'contoso.com' or PartitionKey eq 'AllTenants'" -and $Filter -match "state eq 'Blocked'" }
    }
}

Describe 'Resolve-CIPPIPAllowBlockList' {
    BeforeAll {
        $script:Entries = @(
            [pscustomobject]@{ Range = '203.0.113.0/24'; State = 'Blocked'; Scope = 'AllTenants'; Prefix = 24 }
            [pscustomobject]@{ Range = '203.0.113.0/24'; State = 'Trusted'; Scope = 'Tenant'; Prefix = 24 }
            [pscustomobject]@{ Range = '203.0.113.66'; State = 'Blocked'; Scope = 'Tenant'; Prefix = 32 }
            [pscustomobject]@{ Range = '198.51.100.0/22'; State = 'Blocked'; Scope = 'AllTenants'; Prefix = 22 }
        )
    }

    It 'lets a tenant allow relax an AllTenants block of the same range' {
        (Resolve-CIPPIPAllowBlockList -IPAddress '203.0.113.10' -Entries $script:Entries).State | Should -Be 'Trusted'
    }

    It 'lets the most specific range win, and ignores a client port' {
        (Resolve-CIPPIPAllowBlockList -IPAddress '203.0.113.66:51234' -Entries $script:Entries).State | Should -Be 'Blocked'
        (Resolve-CIPPIPAllowBlockList -IPAddress '198.51.101.200' -Entries $script:Entries).Range | Should -Be '198.51.100.0/22'
    }

    It 'returns nothing for an unlisted, empty or other-family address' {
        Resolve-CIPPIPAllowBlockList -IPAddress '192.0.2.1' -Entries $script:Entries | Should -BeNullOrEmpty
        Resolve-CIPPIPAllowBlockList -IPAddress '' -Entries $script:Entries | Should -BeNullOrEmpty
        Resolve-CIPPIPAllowBlockList -IPAddress '2001:db8::1' -Entries $script:Entries | Should -BeNullOrEmpty
    }
}
