# What a custom managed baseline request sends to CyberDrain must not identify the tenant.
# Test-CIPPManagedBaselineIdentifier finds the identifying text; Protect-CIPPManagedBaselineSnapshot
# removes it from a standard's current value before that value is stored or sent.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Test-CIPPManagedBaselineIdentifier.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Protect-CIPPManagedBaselineSnapshot.ps1')

    $script:Tenant = @('Contoso Ltd', 'contoso.com', 'contoso.onmicrosoft.com', 'contoso', '9f2c7b1e-4a6d-4c3f-8b9a-5e1d2f7c0a44', 'IT')
}

Describe 'Test-CIPPManagedBaselineIdentifier' {
    It 'finds <Found> in "<Text>"' -ForEach @(
        @{ Text = 'send quarantine notices to soc@fabrikam.example'; Found = 'an email address' }
        @{ Text = 'admin@contoso.onmicrosoft.com'; Found = 'an email address' }
        @{ Text = 'Contoso Ltd wants phishing-resistant MFA'; Found = "the tenant's own name, domain or ID" }
        @{ Text = 'https://contoso-my.sharepoint.com/personal'; Found = "the tenant's own name, domain or ID" }
        @{ Text = 'mail.CONTOSO.com'; Found = "the tenant's own name, domain or ID" }
        @{ Text = 'object 0b1e7c4a-9f3d-4e6a-8c2b-2d7f1a9e3c40 is exempt'; Found = 'an ID' }
        @{ Text = 'office address 203.0.113.5'; Found = 'an IP address' }
        @{ Text = '10.0.0.0/8'; Found = 'an IP address' }
        @{ Text = '2001:db8::1'; Found = 'an IP address' }
        @{ Text = 'fe80::1ff:fe23:4567:890a'; Found = 'an IP address' }
        @{ Text = '2001:0db8:85a3:0000:0000:8a2e:0370:7334'; Found = 'an IP address' }
    ) {
        Test-CIPPManagedBaselineIdentifier -Text $Text -TenantIdentifiers $script:Tenant | Should -Be $Found
    }

    It 'finds nothing in "<Text>"' -ForEach @(
        @{ Text = 'Pass the cyber insurance questionnaire and stop external forwarding.' }
        @{ Text = 'Scanners still need SMTP basic authentication. Report only first.' }
        @{ Text = 'The client uses salesforce.com for single sign-on.' }
        @{ Text = 'Quiet hours start at 12:30:45' }
        @{ Text = 'Windows build 10.0.19045.1' }
        @{ Text = 'notcontosoish works with it' }
        @{ Text = '' }
    ) {
        Test-CIPPManagedBaselineIdentifier -Text $Text -TenantIdentifiers $script:Tenant | Should -BeNullOrEmpty
    }

    It 'finds any other host name only when asked to' {
        Test-CIPPManagedBaselineIdentifier -Text 'salesforce.com' | Should -BeNullOrEmpty
        Test-CIPPManagedBaselineIdentifier -Text 'salesforce.com' -AnyDomain | Should -Be 'a domain name'
        Test-CIPPManagedBaselineIdentifier -Text 'https://login.example.org/path' -AnyDomain | Should -Be 'a domain name'
        Test-CIPPManagedBaselineIdentifier -Text 'Audit' -AnyDomain | Should -BeNullOrEmpty
    }
}

Describe 'Protect-CIPPManagedBaselineSnapshot' {
    BeforeAll {
        $script:Definition = [pscustomobject]@{
            name      = 'Sample'
            variables = [pscustomobject]@{ mode = [pscustomobject]@{ options = @([pscustomobject]@{ label = 'Audit'; value = 'Audit' }) } }
            expected  = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.countryNamedLocation'; enabled = '%enabled%' }
        }
        $script:Value = [pscustomobject]@{
            enabled        = $true
            threshold      = 5
            mode           = 'Audit'
            modes          = @('Audit')
            ports          = @(25, 587)
            allowedDomains = @('contoso.com', 'fabrikam.example')
            offenders      = @('Megan Bowen', 'Adele Vance', 'Lee Gu')
            targets        = @([pscustomobject]@{ id = '0b1e7c4a-9f3d-4e6a-8c2b-2d7f1a9e3c40' })
            nobody         = @()
            notify         = 'soc@contoso.com'
            nested         = [pscustomobject]@{
                tenantId = '9f2c7b1e-4a6d-4c3f-8b9a-5e1d2f7c0a44'
                range    = '203.0.113.0/24'
                label    = 'Contoso - block legacy authentication'
                note     = 'Plain words stay'
            }
            '@odata.type'  = '#microsoft.graph.countryNamedLocation'
            banner         = 'x' * 250
            empty          = ''
            nothing        = $null
            'contoso.com'  = 'keyed by a domain'
        }
        $script:Clean = Protect-CIPPManagedBaselineSnapshot -Value $script:Value -TenantIdentifiers $script:Tenant -Definition $script:Definition
    }

    It 'keeps on/off values, numbers, empty values and plain words' {
        $script:Clean.enabled | Should -BeTrue
        $script:Clean.threshold | Should -Be 5
        $script:Clean.mode | Should -Be 'Audit'
        $script:Clean.empty | Should -Be ''
        $script:Clean.nothing | Should -BeNullOrEmpty
        $script:Clean.nested.note | Should -Be 'Plain words stay'
    }

    It 'removes addresses, IDs, ranges and the tenant''s name at any depth' {
        $script:Clean.notify | Should -Be '<redacted>'
        $script:Clean.nested.tenantId | Should -Be '<redacted>'
        $script:Clean.nested.range | Should -Be '<redacted>'
        $script:Clean.nested.label | Should -Be '<redacted>'
    }

    It 'keeps text that appears word for word in the standard''s own definition' {
        $script:Clean.'@odata.type' | Should -Be '#microsoft.graph.countryNamedLocation'
        (Protect-CIPPManagedBaselineSnapshot -Value '#microsoft.graph.countryNamedLocation' -TenantIdentifiers $script:Tenant) | Should -Be '<redacted>'
    }

    It 'replaces long text with its length' {
        $script:Clean.banner | Should -Be '<text, 250 characters>'
    }

    It 'checks property names too' {
        $script:Clean.PSObject.Properties.Name | Should -Not -Contain 'contoso.com'
        $script:Clean.'<redacted>' | Should -Be 'keyed by a domain'
    }

    It 'leaves nothing that names the tenant anywhere in the result' {
        $Json = ConvertTo-Json -Depth 20 -Compress -InputObject $script:Clean
        $Json | Should -Not -Match 'contoso'
        $Json | Should -Not -Match 'fabrikam'
        $Json | Should -Not -Match '9f2c7b1e'
        $Json | Should -Not -Match '203\.0\.113'
    }

    It 'keeps only the length of a list that could name people, mailboxes or devices' {
        $script:Clean.allowedDomains | Should -Be '<2 items>'
        $script:Clean.offenders | Should -Be '<3 items>'
        $script:Clean.targets | Should -Be '<1 item>'
        (ConvertTo-Json -Compress -InputObject $script:Clean) | Should -Not -Match 'Megan|Adele'
    }

    It 'keeps a list whose every entry is a number or the definition''s own text, still as a list' {
        , $script:Clean.modes | Should -BeOfType [array]
        $script:Clean.modes | Should -Be @('Audit')
        $script:Clean.ports | Should -Be @(25, 587)
        , $script:Clean.nobody | Should -BeOfType [array]
        $script:Clean.nobody.Count | Should -Be 0
    }

    It 'keeps two property names apart when both are removed' {
        $Result = Protect-CIPPManagedBaselineSnapshot -Value ([ordered]@{ 'a.contoso.com' = 1; 'b.contoso.com' = 2 }) -TenantIdentifiers $script:Tenant

        @($Result.PSObject.Properties).Count | Should -Be 2
        @($Result.PSObject.Properties.Value) | Should -Be @(1, 2)
    }

    It 'never passes an ID that arrives as a real GUID value' {
        Protect-CIPPManagedBaselineSnapshot -Value ([guid]'0b1e7c4a-9f3d-4e6a-8c2b-2d7f1a9e3c40') | Should -Be '<redacted>'
    }
}
