# Converting Internet Access custom rules between destination lines and Graph's rule shape.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPGSAForwardingRule.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertFrom-CIPPGSAForwardingRule.ps1')
}

Describe 'ConvertTo-CIPPGSAForwardingRule' {
    It 'groups destinations into one rule per type and protocol, in the shape the portal stores' {
        $Rules = @(ConvertTo-CIPPGSAForwardingRule -Destinations '*.Contoso.com', '10.0.0.0/8', '198.51.100.1 - 198.51.100.20', '203.0.113.5', 'intranet.contoso.com' -Action bypass -Ports '')
        @($Rules.ForEach({ "$($_.ruleType)/$($_.protocol)" })) | Should -Be @('fqdn/tcp', 'fqdn/udp', 'ipSubnet/tcp', 'ipSubnet/udp', 'ipRange/tcp', 'ipRange/udp', 'ipAddress/tcp', 'ipAddress/udp')
        ConvertTo-Json -Compress -Depth 6 -InputObject $Rules[0] | Should -Be '{"@odata.type":"#microsoft.graph.networkaccess.internetAccessForwardingRule","name":"CIPP bypass fqdn TCP","ruleType":"fqdn","action":"bypass","protocol":"tcp","ports":["0-65535"],"destinations":[{"@odata.type":"#microsoft.graph.networkaccess.fqdn","value":"*.contoso.com"},{"@odata.type":"#microsoft.graph.networkaccess.fqdn","value":"intranet.contoso.com"}]}'
        ConvertTo-Json -Compress -Depth 6 -InputObject $Rules[4].destinations | Should -Be '[{"@odata.type":"#microsoft.graph.networkaccess.ipRange","beginAddress":"198.51.100.1","endAddress":"198.51.100.20"}]'
    }

    It 'uses the configured ports' {
        @(ConvertTo-CIPPGSAForwardingRule -Destinations 'a.contoso.com' -Action forward -Ports '443, 8000-8100')[0].ports | Should -Be @('443', '8000-8100')
    }

    It 'returns no rules for no destinations, so an empty list clears the policy' {
        @(ConvertTo-CIPPGSAForwardingRule -Destinations @() -Action bypass -Ports '').Count | Should -Be 0
    }

    It 'refuses a destination or port it cannot place' {
        { ConvertTo-CIPPGSAForwardingRule -Destinations 'https://contoso.com/x' -Action bypass -Ports '' } | Should -Throw -ExceptionType ([System.ArgumentException])
        { ConvertTo-CIPPGSAForwardingRule -Destinations '10.0.0.0/33' -Action bypass -Ports '' } | Should -Throw -ExceptionType ([System.ArgumentException])
        { ConvertTo-CIPPGSAForwardingRule -Destinations 'contoso.com' -Action bypass -Ports 'https' } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'ConvertFrom-CIPPGSAForwardingRule' {
    It 'reads rules back as one sorted entry per destination, merging TCP and UDP' {
        $Built = @(ConvertTo-CIPPGSAForwardingRule -Destinations 'b.contoso.com', '198.51.100.1-198.51.100.20', 'a.contoso.com' -Action bypass -Ports '')
        $Read = @(ConvertFrom-CIPPGSAForwardingRule -Rules ($Built | ConvertTo-Json -Depth 10 | ConvertFrom-Json))
        @($Read.ForEach({ "$($_.destination) $($_.ports) $($_.protocols)" })) | Should -Be @('198.51.100.1-198.51.100.20 0-65535 tcp,udp', 'a.contoso.com 0-65535 tcp,udp', 'b.contoso.com 0-65535 tcp,udp')
    }

    It 'keeps a destination listed for one protocol only as that protocol, and separate port sets apart' {
        $Rules = @(
            [pscustomobject]@{ protocol = 'tcp'; ports = @('443'); destinations = @([pscustomobject]@{ value = 'x.contoso.com' }) }
            [pscustomobject]@{ protocol = 'udp'; ports = @('53'); destinations = @([pscustomobject]@{ value = 'x.contoso.com' }) }
        )
        @((ConvertFrom-CIPPGSAForwardingRule -Rules $Rules).ForEach({ "$($_.ports) $($_.protocols)" })) | Should -Be @('443 tcp', '53 udp')
    }
}
