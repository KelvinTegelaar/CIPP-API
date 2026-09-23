BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
}

Describe 'ConvertTo-CIPPBecHostAddress' {
    It 'drops the port from an IPv4 client address' {
        ConvertTo-CIPPBecHostAddress -Address '115.70.126.106:28297' | Should -Be '115.70.126.106'
        ConvertTo-CIPPBecHostAddress -Address ' 115.70.126.106 ' | Should -Be '115.70.126.106'
    }

    It 'drops the port and brackets from an IPv6 client address' {
        ConvertTo-CIPPBecHostAddress -Address '[2001:db8::1]:443' | Should -Be '2001:db8::1'
        ConvertTo-CIPPBecHostAddress -Address '2001:db8::1' | Should -Be '2001:db8::1'
    }

    It 'returns null for an empty address and leaves other text alone' {
        ConvertTo-CIPPBecHostAddress -Address '' | Should -BeNullOrEmpty
        ConvertTo-CIPPBecHostAddress -Address $null | Should -BeNullOrEmpty
        ConvertTo-CIPPBecHostAddress -Address '<redacted>' | Should -Be '<redacted>'
    }
}
