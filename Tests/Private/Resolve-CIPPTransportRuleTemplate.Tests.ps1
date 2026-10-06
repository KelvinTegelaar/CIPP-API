BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTextReplacement { param($Text, $TenantFilter, [switch]$EscapeForJson) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPTransportRuleTemplate.ps1')
}

Describe 'Resolve-CIPPTransportRuleTemplate' {
    BeforeEach {
        Mock Get-CIPPTextReplacement { $Text -replace '%tenantname%', "Contoso($TenantFilter)" }
    }

    It 'resolves top-level strings, strings inside arrays and nested objects' {
        $Template = '{"name":"Block %tenantname%","ExceptIfSenderDomainIs":["%tenantname%.com","fabrikam.com"],"Nested":{"Text":"Hi %tenantname%"}}' | ConvertFrom-Json
        $Result = Resolve-CIPPTransportRuleTemplate -Template $Template -TenantFilter 'contoso.com'
        $Result.name | Should -Be 'Block Contoso(contoso.com)'
        @($Result.ExceptIfSenderDomainIs) | Should -Be @('Contoso(contoso.com).com', 'fabrikam.com')
        $Result.Nested.Text | Should -Be 'Hi Contoso(contoso.com)'
    }

    It 'passes booleans, numbers and nulls through and keeps single-item arrays as arrays' {
        $Template = '{"Enabled":true,"Priority":3,"Comments":null,"SentTo":["a@%tenantname%"]}' | ConvertFrom-Json
        $Result = Resolve-CIPPTransportRuleTemplate -Template $Template -TenantFilter 'contoso.com'
        $Result.Enabled | Should -BeOfType [bool]
        $Result.Enabled | Should -BeTrue
        $Result.Priority | Should -Be 3
        $Result.Comments | Should -BeNullOrEmpty
        , $Result.SentTo | Should -BeOfType [array]
        $Result.SentTo[0] | Should -Be 'a@Contoso(contoso.com)'
    }

    It 'returns a copy and leaves the source template untouched' {
        $Template = '{"name":"%tenantname% rule"}' | ConvertFrom-Json
        $null = Resolve-CIPPTransportRuleTemplate -Template $Template -TenantFilter 'contoso.com'
        $Template.name | Should -Be '%tenantname% rule'
    }
}
