# A tenant without Defender for Office 365 has no impersonation or mailbox-intelligence settings, so
# Set-AntiPhishPolicy must never be sent them there.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineAntiPhishPolicyState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineExoPolicyRule.ps1')

    $script:MdoParams = @('EnableMailboxIntelligence', 'EnableMailboxIntelligenceProtection', 'EnableTargetedDomainsProtection', 'EnableTargetedUserProtection', 'EnableOrganizationDomainsProtection', 'EnableSimilarUsersSafetyTips', 'EnableSimilarDomainsSafetyTips', 'EnableUnusualCharactersSafetyTips', 'PhishThresholdLevel', 'TargetedUserProtectionAction')
    $script:Item = [PSCustomObject]@{ Variables = [PSCustomObject]@{
            name                         = 'CIPP Default Anti-Phishing Policy'
            AuthenticationFailAction     = 'Quarantine'
            PhishThresholdLevel          = '2'
            TargetedUserProtectionAction = 'Quarantine'
        }
    }
    $script:Remediate = [PSCustomObject]@{ executor = 'ExoPolicyRule'; policyCmdlet = 'AntiPhishPolicy'; ruleCmdlet = 'AntiPhishRule'; policyParams = [PSCustomObject]@{ Enabled = $true }; ruleParams = [PSCustomObject]@{ Priority = 0 } }
}

Describe 'AntiPhishPolicy baseline licensing' {
    BeforeEach {
        $script:Cache = @{
            ExoAntiPhishPolicies = @([PSCustomObject]@{ Name = 'CIPP Default Anti-Phishing Policy' })
            ExoAntiPhishRules    = @([PSCustomObject]@{ Name = 'CIPP Default Anti-Phishing Policy Rule'; AntiPhishPolicy = 'CIPP Default Anti-Phishing Policy'; Priority = 0 })
            ExoAcceptedDomains   = @([PSCustomObject]@{ Name = 'contoso.com' })
        }
        Mock Get-CIPPBaselineCacheRows { $script:Cache[$Type] }
        $script:Sent = @{}
        Mock New-ExoRequest { $script:Sent[$cmdlet] = $cmdParams }
    }

    It 'writes no Defender for Office 365 settings to an unlicensed tenant' {
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ EXCHANGE_S_STANDARD = $true } }
        $State = Get-CIPPBaselineAntiPhishPolicyState -Item $script:Item -TenantFilter 'contoso.com'
        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current $State.Current

        $script:Sent['Set-AntiPhishPolicy'].Keys | Where-Object { $_ -in $script:MdoParams } | Should -BeNullOrEmpty
        $script:Sent['Set-AntiPhishPolicy'].Enabled | Should -BeTrue
    }

    It 'still writes them to a licensed tenant' {
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ ATP_ENTERPRISE = $true } }
        $State = Get-CIPPBaselineAntiPhishPolicyState -Item $script:Item -TenantFilter 'contoso.com'
        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current $State.Current

        $script:Sent['Set-AntiPhishPolicy'].EnableMailboxIntelligence | Should -BeTrue
        $script:Sent['Set-AntiPhishPolicy'].PhishThresholdLevel | Should -Be 2
        $script:Sent['Set-AntiPhishPolicy'].TargetedUserProtectionAction | Should -Be 'Quarantine'
    }
}
