# Unit tests for Get-CippRequestIPAddress: first x-forwarded-for hop with any port
# suffix and IPv6 brackets stripped; missing header yields an empty string.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Private/Authentication/Get-CippRequestIPAddress.ps1')

    function New-IPRequest {
        param($ForwardedFor)
        $Headers = @{}
        if ($null -ne $ForwardedFor) { $Headers['x-forwarded-for'] = $ForwardedFor }
        [pscustomobject]@{ Headers = $Headers }
    }
}

Describe 'Get-CippRequestIPAddress' {
    It 'returns a plain IPv4 unchanged' {
        Get-CippRequestIPAddress -Request (New-IPRequest '1.2.3.4') | Should -Be '1.2.3.4'
    }

    It 'strips a port from IPv4' {
        Get-CippRequestIPAddress -Request (New-IPRequest '1.2.3.4:8080') | Should -Be '1.2.3.4'
    }

    It 'strips brackets and port from bracketed IPv6' {
        Get-CippRequestIPAddress -Request (New-IPRequest '[::1]:443') | Should -Be '::1'
    }

    It 'returns bare IPv6 unchanged' {
        Get-CippRequestIPAddress -Request (New-IPRequest '2001:db8::1') | Should -Be '2001:db8::1'
    }

    It 'takes only the first hop of a multi-hop header' {
        Get-CippRequestIPAddress -Request (New-IPRequest '9.9.9.9, 8.8.8.8, 7.7.7.7') | Should -Be '9.9.9.9'
    }

    It 'returns an empty string when the header is missing' {
        Get-CippRequestIPAddress -Request (New-IPRequest $null) | Should -Be ''
    }
}
