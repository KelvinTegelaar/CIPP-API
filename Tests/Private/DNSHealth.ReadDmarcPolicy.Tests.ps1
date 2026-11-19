# A subdomain with no DMARC record of its own is covered by its parent's subdomain policy (sp); reporting it as
# having no DMARC made every verified subdomain look unprotected.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Latest = Get-ChildItem (Join-Path $BackendRoot 'Modules/DNSHealth') -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    Import-Module (Join-Path $Latest.FullName 'DNSHealth.psd1') -Force -ErrorAction Stop

    # Fake DNS: TXT answers keyed by query name; anything else is NXDOMAIN.
    $script:Txt = @{}
    function New-Answer($Name) {
        if ($script:Txt.ContainsKey($Name)) { [pscustomobject]@{ Status = 0; Answer = @([pscustomobject]@{ data = $script:Txt[$Name] }) } }
        else { [pscustomobject]@{ Status = 3; Answer = @() } }
    }
}

Describe 'Read-DmarcPolicy parent fallback' {
    BeforeEach {
        $script:Txt = @{}
        Mock Resolve-DnsHttpsQuery -ModuleName DNSHealth { New-Answer $Domain }
    }

    It 'applies the parent''s subdomain policy to a subdomain without its own record' {
        $script:Txt['_dmarc.contoso.com'] = 'v=DMARC1; p=reject; sp=quarantine; rua=mailto:dmarc@contoso.com'
        $Result = Read-DmarcPolicy -Domain 'mail.contoso.com'
        $Result.InheritedFrom | Should -Be 'contoso.com'
        $Result.Record | Should -Be 'v=DMARC1; p=reject; sp=quarantine; rua=mailto:dmarc@contoso.com'
        $Result.Policy | Should -Be 'quarantine'
        $Result.SubdomainPolicy | Should -Be 'quarantine'
        $Result.ValidationPasses[0] | Should -Be 'This domain has no DMARC record of its own, so the subdomain policy of contoso.com applies.'
        $Result.ValidationFails | Should -Not -Contain 'This domain does not have a DMARC record.'
    }

    It 'falls back to p when the parent sets no sp' {
        $script:Txt['_dmarc.contoso.com'] = 'v=DMARC1; p=reject'
        (Read-DmarcPolicy -Domain 'mail.contoso.com').Policy | Should -Be 'reject'
    }

    It 'uses the nearest parent that has a record' {
        $script:Txt['_dmarc.contoso.com'] = 'v=DMARC1; p=none'
        $script:Txt['_dmarc.eu.contoso.com'] = 'v=DMARC1; p=reject; sp=reject'
        (Read-DmarcPolicy -Domain 'mail.eu.contoso.com').InheritedFrom | Should -Be 'eu.contoso.com'
    }

    It 'keeps the domain''s own record when it has one' {
        $script:Txt['_dmarc.contoso.com'] = 'v=DMARC1; p=reject'
        $script:Txt['_dmarc.mail.contoso.com'] = 'v=DMARC1; p=none'
        $Result = Read-DmarcPolicy -Domain 'mail.contoso.com'
        $Result.InheritedFrom | Should -BeNullOrEmpty
        $Result.Policy | Should -Be 'none'
    }

    It 'reports no record, without querying the top-level domain, when no parent has one' {
        $Result = Read-DmarcPolicy -Domain 'mail.contoso.com'
        $Result.Record | Should -BeNullOrEmpty
        $Result.ValidationFails | Should -Contain 'This domain does not have a DMARC record.'
        Should -Invoke Resolve-DnsHttpsQuery -ModuleName DNSHealth -Times 0 -ParameterFilter { $Domain -eq '_dmarc.com' }
    }

    It 'accepts ~all on a subdomain whose inherited policy is reject at 100%' {
        $script:Txt['mail.contoso.com'] = 'v=spf1 ip4:192.0.2.1 ~all'
        $script:Txt['_dmarc.contoso.com'] = 'v=DMARC1; p=reject'
        $Spf = Read-SpfRecord -Domain 'mail.contoso.com'
        $Spf.ValidationPasses | Should -Contain 'The SPF record ends with a soft fail qualifier (~all). With DMARC p=reject at 100%, this is acceptable as DMARC will enforce rejection.'
        $Spf.ValidationFails | Should -Not -Contain 'The SPF record should end in -all to prevent spamming.'
    }

    It 'does not look above a root domain' {
        $null = Read-DmarcPolicy -Domain 'contoso.com'
        Should -Invoke Resolve-DnsHttpsQuery -ModuleName DNSHealth -Times 1 -Exactly
    }
}
