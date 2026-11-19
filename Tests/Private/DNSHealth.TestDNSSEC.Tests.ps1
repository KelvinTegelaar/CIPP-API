# A subdomain inside a signed zone has no DNSKEY at its own name; the authenticated (AD) empty answer is the proof
# that DNSSEC covers it. Reporting it as not set up flagged every subdomain of a signed domain.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Latest = Get-ChildItem (Join-Path $BackendRoot 'Modules/DNSHealth') -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    Import-Module (Join-Path $Latest.FullName 'DNSHealth.psd1') -Force -ErrorAction Stop
}

Describe 'Test-DNSSEC' {
    It 'passes a name inside a signed zone through the zone apex' {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { [pscustomobject]@{ Status = 0; AD = $true; Answer = @(); Authority = @([pscustomobject]@{ name = 'contoso.com.' }) } }
        $Result = Test-DNSSEC -Domain 'mail.contoso.com'
        $Result.ValidationFails | Should -BeNullOrEmpty
        $Result.ValidationPasses | Should -Be @('DNSSEC is enabled and validated for this domain through the signed zone contoso.com.')
    }

    It 'still fails an unsigned name with no keys' {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { [pscustomobject]@{ Status = 0; AD = $false; Answer = @() } }
        (Test-DNSSEC -Domain 'mail.contoso.com').ValidationFails | Should -Be @('DNSSEC is not set up for this domain.')
    }

    It 'still passes a zone apex with validated keys' {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { [pscustomobject]@{ Status = 0; AD = $true; Answer = @([pscustomobject]@{ data = '257 3 13 key' }) } }
        (Test-DNSSEC -Domain 'contoso.com').ValidationPasses | Should -Be @('DNSSEC is enabled and validated for this domain.')
    }
}
