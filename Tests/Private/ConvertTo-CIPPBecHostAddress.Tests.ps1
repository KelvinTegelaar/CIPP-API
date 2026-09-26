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

    It 'writes one host one way: IPv6 compressed and lower case, IPv4-mapped as plain IPv4' {
        ConvertTo-CIPPBecHostAddress -Address '2603:10A6:20B:4C::12' | Should -Be '2603:10a6:20b:4c::12'
        ConvertTo-CIPPBecHostAddress -Address '2603:10a6:020b:004c:0000:0000:0000:0012' | Should -Be '2603:10a6:20b:4c::12'
        ConvertTo-CIPPBecHostAddress -Address '::ffff:203.0.113.10' | Should -Be '203.0.113.10'
        ConvertTo-CIPPBecHostAddress -Address '[::ffff:203.0.113.10]:443' | Should -Be '203.0.113.10' -Because 'the port used to stay glued on and split the host per connection'
    }

    It 'gives the /64 of an IPv6 address with -Network, and the host of an IPv4 one' {
        ConvertTo-CIPPBecHostAddress -Address '[2001:DB8:1:2:a1b2:c3d4:e5f6:1]:51234' -Network | Should -Be '2001:db8:1:2::/64'
        ConvertTo-CIPPBecHostAddress -Address '2001:db8:1:2::99' -Network | Should -Be '2001:db8:1:2::/64'
        ConvertTo-CIPPBecHostAddress -Address '203.0.113.10:80' -Network | Should -Be '203.0.113.10'
    }

    It 'returns null for an empty address and leaves other text alone' {
        ConvertTo-CIPPBecHostAddress -Address '' | Should -BeNullOrEmpty
        ConvertTo-CIPPBecHostAddress -Address $null | Should -BeNullOrEmpty
        ConvertTo-CIPPBecHostAddress -Address '<redacted>' | Should -Be '<redacted>'
        ConvertTo-CIPPBecHostAddress -Address 'XXX.XXX.XXX.XXX' | Should -Be 'XXX.XXX.XXX.XXX'
        ConvertTo-CIPPBecHostAddress -Address '12345' | Should -Be '12345' -Because '.NET would read a bare number as IPv4'
    }
}
