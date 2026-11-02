# The Exchange protection hooks must find a rule the Defender portal created (named after its policy)
# and grade the configured policy rather than a legacy CIPP default that sorts earlier in the cache.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'
    $env:CIPPRootPath = $script:RepoRoot

    function Get-CIPPBaselineWorkItems { param($TenantFilter) }
    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) $Text }
    function Get-CIPPIntunePolicyGraphPath { param($UrlName) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Get-CIPPBaselineDefinition.ps1')
    foreach ($Name in 'DetectIntuneDrift', 'SafeLinksPolicy', 'SafeAttachmentPolicy', 'MalwareFilterPolicy', 'AntiPhishPolicy') {
        . (Join-Path $Baselines "PrepareHooks/Get-CIPPBaseline${Name}State.ps1")
    }
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Exchange protection rule ownership' {
    BeforeEach {
        $script:Cache = @{ ExoAcceptedDomains = @([PSCustomObject]@{ Name = 'contoso.com' }) }
        Mock Get-CIPPBaselineCacheRows { $script:Cache[$Type] }
    }

    It '<Hook>: finds a portal rule named after its policy and grades the configured policy (legacy default: <Legacy>)' -ForEach @(
        @{ Hook = 'SafeLinks'; Policies = 'ExoSafeLinksPolicies'; Rules = 'ExoSafeLinksRules'; Link = 'SafeLinksPolicy'; Legacy = 'Default SafeLinks Policy' }
        @{ Hook = 'SafeAttachment'; Policies = 'ExoSafeAttachmentPolicies'; Rules = 'ExoSafeAttachmentRules'; Link = 'SafeAttachmentPolicy'; Legacy = 'Default Safe Attachment Policy' }
        @{ Hook = 'AntiPhish'; Policies = 'ExoAntiPhishPolicies'; Rules = 'ExoAntiPhishRules'; Link = 'AntiPhishPolicy'; Legacy = 'Default Anti-Phishing Policy' }
        @{ Hook = 'MalwareFilter'; Policies = 'ExoMalwareFilterPolicies'; Rules = 'ExoMalwareFilterRules'; Link = 'MalwareFilterPolicy'; Legacy = $null }
        @{ Hook = 'SafeLinks'; Policies = 'ExoSafeLinksPolicies'; Rules = 'ExoSafeLinksRules'; Link = 'SafeLinksPolicy'; Legacy = $null }
        @{ Hook = 'SafeAttachment'; Policies = 'ExoSafeAttachmentPolicies'; Rules = 'ExoSafeAttachmentRules'; Link = 'SafeAttachmentPolicy'; Legacy = $null }
        @{ Hook = 'AntiPhish'; Policies = 'ExoAntiPhishPolicies'; Rules = 'ExoAntiPhishRules'; Link = 'AntiPhishPolicy'; Legacy = $null }
    ) {
        $script:Cache[$Policies] = @(
            if ($Legacy) { [PSCustomObject]@{ Name = $Legacy } }
            [PSCustomObject]@{ Name = 'Protection Policy' }
        )
        $script:Cache[$Rules] = @([PSCustomObject]@{ Name = 'Protection Policy'; $Link = 'Protection Policy'; Priority = 0; RecipientDomainIs = @('contoso.com'); State = 'Enabled' })
        $Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{ name = 'Protection Policy' } }

        $State = & "Get-CIPPBaseline${Hook}PolicyState" -Item $Item -TenantFilter $script:Tenant

        $State.Current.policyName | Should -Be 'Protection Policy'
        $State.Current.ruleExists | Should -BeTrue
        $State.Current.ruleName | Should -Be 'Protection Policy'
        $State.Current.rule.name | Should -Be $State.Expected.rule.name
        $State.Current.rule.policy | Should -Be $State.Expected.rule.policy
        $State.Current.rule.recipientDomainIs | Should -Be $State.Expected.rule.recipientDomainIs
    }

    It 'keeps finding a CIPP-named rule when no rule links to the policy yet' {
        $script:Cache['ExoSafeLinksPolicies'] = @([PSCustomObject]@{ Name = 'Protection Policy' })
        $script:Cache['ExoSafeLinksRules'] = @([PSCustomObject]@{ Name = 'Protection Policy_Rule'; SafeLinksPolicy = 'Something Else' })
        $State = Get-CIPPBaselineSafeLinksPolicyState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ name = 'Protection Policy' } }) -TenantFilter $script:Tenant
        $State.Current.ruleName | Should -Be 'Protection Policy_Rule'
        $State.Current.ruleLinkedPolicy | Should -Be 'Something Else'
    }
}
