# A resolver that fails to answer must not read as a domain with no MX records: the Domain Analyser saved that as every
# record removed, and the MX change alert fired twice (records gone, records back) for each domain on a bad DNS night.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Latest = Get-ChildItem (Join-Path $BackendRoot 'Modules/DNSHealth') -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    Import-Module (Join-Path $Latest.FullName 'DNSHealth.psd1') -Force -ErrorAction Stop
}

Describe 'Read-MXRecord lookup failures' {
    It 'flags a resolver error as a failed lookup, not missing records' {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { throw 'Exception querying resolver Google: timed out' }
        $Result = Read-MXRecord -Domain 'contoso.com'
        $Result.LookupFailed | Should -BeTrue
        $Result.Records | Should -HaveCount 0
        $Result.MailProvider | Should -BeNullOrEmpty
        $Result.ValidationFails | Should -Match 'could not be retrieved \(Exception querying resolver Google: timed out\)'
    }

    It 'flags a <Name> answer as a failed lookup' -ForEach @(
        @{ Name = 'SERVFAIL'; Answer = [pscustomobject]@{ Status = 2; AD = $true } }
        @{ Name = 'REFUSED'; Answer = [pscustomobject]@{ Status = 5 } }
    ) {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { $Answer }
        (Read-MXRecord -Domain 'contoso.com').LookupFailed | Should -BeTrue
    }

    It 'keeps the DNSSEC message for a SERVFAIL without validation' {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { [pscustomobject]@{ Status = 2; AD = $false } }
        $Result = Read-MXRecord -Domain 'contoso.com'
        $Result.LookupFailed | Should -BeTrue
        $Result.ValidationFails | Should -Be @('DNSSEC validation failed.')
    }

    It 'reports a real <Name> as no MX records' -ForEach @(
        @{ Name = 'NXDOMAIN'; Answer = [pscustomobject]@{ Status = 3 } }
        @{ Name = 'empty answer'; Answer = [pscustomobject]@{ Status = 0; Answer = @() } }
    ) {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { $Answer }
        $Result = Read-MXRecord -Domain 'contoso.com'
        $Result.LookupFailed | Should -BeFalse
        $Result.ValidationFails | Should -Match 'There are no mail exchanger records'
        $Result.MailProvider.Name | Should -Be 'Null'
    }

    It 'returns the records for a good answer' {
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { [pscustomobject]@{ Status = 0; Answer = @([pscustomobject]@{ Data = '10 contoso-com.mail.protection.outlook.com.' }) } }
        $Result = Read-MXRecord -Domain 'contoso.com'
        $Result.LookupFailed | Should -BeFalse
        $Result.Records.Hostname | Should -Be 'contoso-com.mail.protection.outlook.com.'
        $Result.MailProvider.Name | Should -Be 'Microsoft 365'
    }
}
