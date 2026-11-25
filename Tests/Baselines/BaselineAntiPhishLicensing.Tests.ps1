# A tenant without Defender for Office 365 has no impersonation or mailbox-intelligence settings, so
# Set-AntiPhishPolicy must never be sent them there.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function Get-CIPPBaselineCacheRows { [CmdletBinding()] param($TenantFilter, $Type, $CollectorType, $CollectorArgs, $Fields) }
    function Get-CIPPDbItem { [CmdletBinding()] param($TenantFilter, $Type, [switch]$CountsOnly) }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $UseSystemMailbox) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }

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

Describe 'AntiPhishPolicy impersonation lists' {
    BeforeAll {
        function Use-DirectoryFixture {
            param([int]$Count = 1)
            $script:Cache['Users'] = @(
                foreach ($I in 1..$Count) {
                    [PSCustomObject]@{ id = "id-$I"; userPrincipalName = "p$I@contoso.onmicrosoft.com"; accountEnabled = $true; userType = 'Member'; assignedLicenses = @('sku') }
                }
            )
            $script:Cache['Mailboxes'] = @(
                foreach ($I in 1..$Count) {
                    [PSCustomObject]@{ ExternalDirectoryObjectId = "id-$I"; displayName = "Person $I"; primarySmtpAddress = "p$I@contoso.com"; recipientTypeDetails = 'UserMailbox' }
                }
            )
        }

        function Get-PolicyState {
            param($Variables = @{})
            if (-not $Variables.ContainsKey('ImpersonationUserScope')) { $Variables['ImpersonationUserScope'] = 'AllLicensed' }
            Get-CIPPBaselineAntiPhishPolicyState -Item @{ Variables = [PSCustomObject]$Variables } -TenantFilter 'contoso.com'
        }
    }

    BeforeEach {
        $script:Policy = [PSCustomObject]@{ Name = 'CIPP Default Anti-Phishing Policy'; PhishThresholdLevel = 1; TargetedUsersToProtect = @(); TargetedDomainsToProtect = @() }
        $script:Cache = @{
            ExoAntiPhishPolicies = @($script:Policy)
            ExoAntiPhishRules    = @([PSCustomObject]@{ Name = 'CIPP Default Anti-Phishing Policy Rule'; AntiPhishPolicy = 'CIPP Default Anti-Phishing Policy'; Priority = 0 })
            ExoAcceptedDomains   = @([PSCustomObject]@{ Name = 'contoso.com'; DomainName = 'contoso.com' })
        }
        Use-DirectoryFixture
        Mock Get-CIPPBaselineCacheRows { if ($Fields) { $script:Cache[$Type] | Select-Object $Fields } else { $script:Cache[$Type] } }
        Mock Get-CIPPDbItem { [PSCustomObject]@{ DataCount = $script:Cache[$Type].Count; Timestamp = [DateTimeOffset]::UtcNow } }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ EXCHANGE_S_ENTERPRISE = $true; ATP_ENTERPRISE = $true } }
        Mock Write-LogMessage {}
        $script:Sent = @{}
        Mock New-ExoRequest { $script:Sent[$cmdlet] = $cmdParams }
    }

    It 'renames internal entries and keeps an external entry added after collection' {
        Use-DirectoryFixture 2
        $script:Cache['Users'][1].accountEnabled = $false
        $script:Cache['Mailboxes'][0].primarySmtpAddress = 'P1@contoso.com'
        $script:Cache['ExoAcceptedDomains'][0].Name = 'fabrikam.com'
        $script:Policy.TargetedUsersToProtect = @('person 1;p1@contoso.com', 'PERSON 1;p1@contoso.com', 'Counsel;counsel@fabrikam.com')
        $Live = [System.Collections.Generic.List[string]]::new([string[]]$script:Policy.TargetedUsersToProtect)
        $Live.Add('Partner;partner@fabrikam.com')

        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current (Get-PolicyState).Current
        $Change = $script:Sent['Set-AntiPhishPolicy'].TargetedUsersToProtect
        $Change.'@odata.type' | Should -BeExactly '#Exchange.GenericHashTable'
        $Change['Add'] | Should -BeExactly @('Person 1;p1@contoso.com')
        $Change['Remove'] | Should -BeExactly @('PERSON 1;p1@contoso.com', 'person 1;p1@contoso.com')
        foreach ($Entry in $Change['Remove']) { $Live.Remove($Entry) | Should -BeTrue }
        $Live.AddRange($Change['Add'])
        $Live.ToArray() | Should -BeExactly @('Counsel;counsel@fabrikam.com', 'Partner;partner@fabrikam.com', 'Person 1;p1@contoso.com')

        $script:Policy.TargetedUsersToProtect = $Live.ToArray()
        $State = Get-PolicyState
        $State.Current.targetedUsersToProtect | Should -BeExactly 'All licensed users (3)'
        $State.Current.extraPolicyParams.PSObject.Properties.Name | Should -Not -Contain 'TargetedUsersToProtect'
    }

    It 'sends the full user list when creating the policy' {
        Use-DirectoryFixture 2
        $script:Cache['ExoAntiPhishPolicies'] = @([PSCustomObject]@{ Name = 'Office365 AntiPhish Default' })
        $State = Get-PolicyState @{ TargetedUsersToProtect = @('p2@contoso.com', 'Executive;P2@contoso.com') }
        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current $State.Current

        $script:Sent['New-AntiPhishPolicy'].TargetedUsersToProtect | Should -BeExactly @('Executive;p2@contoso.com', 'Person 1;p1@contoso.com')
    }

    It 'leaves out disabled and soft-deleted mailboxes' {
        Use-DirectoryFixture 3
        $script:Cache['Mailboxes'][1] | Add-Member -NotePropertyName AccountDisabled -NotePropertyValue $true
        $script:Cache['Mailboxes'][2] | Add-Member -NotePropertyName WhenSoftDeleted -NotePropertyValue '2026-01-01T00:00:00Z'
        $script:Cache['ExoAntiPhishPolicies'] = @([PSCustomObject]@{ Name = 'Office365 AntiPhish Default' })
        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current (Get-PolicyState).Current

        $script:Sent['New-AntiPhishPolicy'].TargetedUsersToProtect | Should -BeExactly @('Person 1;p1@contoso.com')
    }

    It 'counts preserved entries towards the automatic 350-entry cap and still fixes other drift' {
        $script:Policy.TargetedUsersToProtect = @('Counsel;counsel@fabrikam.com', 'COUNSEL;counsel@fabrikam.com')
        Use-DirectoryFixture 348
        $AtLimit = Get-PolicyState
        $AtLimit.Expected.targetedUsersToProtect | Should -BeExactly 'All licensed users (350)'
        $AtLimit.Current.extraPolicyParams.TargetedUsersToProtect['Add'].Count | Should -Be 348

        Use-DirectoryFixture 349
        $OverLimit = Get-PolicyState @{ PhishThresholdLevel = '3' }
        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current $OverLimit.Current
        $OverLimit.Expected.PSObject.Properties.Name | Should -Not -Contain 'targetedUsersToProtect'
        $script:Sent['Set-AntiPhishPolicy'].Keys | Should -Not -Contain 'TargetedUsersToProtect'
        $script:Sent['Set-AntiPhishPolicy'].PhishThresholdLevel | Should -Be 3
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*come to 351*' }
    }

    It 'withholds automatic user changes when the directory cache is stale' {
        $script:Policy.TargetedUsersToProtect = @('New Hire;new.hire@contoso.com')
        Mock Get-CIPPDbItem { [PSCustomObject]@{ DataCount = $script:Cache[$Type].Count; Timestamp = [DateTimeOffset]::UtcNow.AddDays(-10) } } -ParameterFilter { $Type -eq 'Users' }
        $State = Get-PolicyState @{ PhishThresholdLevel = '3' }
        Invoke-CIPPBaselineExoPolicyRule -Remediate $script:Remediate -TenantFilter 'contoso.com' -Current $State.Current

        $State.Expected.PSObject.Properties.Name | Should -Not -Contain 'targetedUsersToProtect'
        $script:Sent['Set-AntiPhishPolicy'].Keys | Should -Not -Contain 'TargetedUsersToProtect'
        $script:Sent['Set-AntiPhishPolicy'].PhishThresholdLevel | Should -Be 3
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*Users cache*48 hours*' }
    }

    Context 'through the engine' {
        BeforeAll {
            function Get-CippTable { param($tablename) @{} }
            function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
            function Get-CIPPAzDataTableEntity { param($Filter) }
            function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
            function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
            function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
            function Send-CIPPBaselineAlert { param($Result) }
            function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
            function Get-CIPPBaselineDefinition { param($Name) }
            function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
            function Get-CippException { param($Exception) }

            . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
            . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
            . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
            . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
            . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')
            $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Defender Standards/AntiPhishPolicy.json') -Raw | ConvertFrom-Json

            function Invoke-PolicyStandard {
                param($Variables)
                $Item = @{ TenantFilter = 'contoso.com'; Standard = 'AntiPhishPolicy'; BaseName = 'AntiPhishPolicy'; Variables = [PSCustomObject]$Variables; Tiers = @(); RemediateEnabled = $true }
                Invoke-CIPPBaselineStandard -Item $Item -Mode 'run'
            }
        }

        BeforeEach {
            Mock Get-CIPPBaselineDefinition { $script:Definition }
            Mock Set-CIPPBaselineResult {}
            Mock Get-CIPPTextReplacement { $Text.Replace('"%keypeople%"', '"CEO;CEO@contoso.com","Chief Executive;ceo@contoso.com","Finance 95% to 100%;finance@contoso.com"') }
        }

        It 'leaves existing protected users alone and remediates other settings when the scope is <Case>' -ForEach @(
            @{ Case = 'missing'; Variables = @{} }
            @{ Case = 'null'; Variables = @{ ImpersonationUserScope = $null } }
        ) {
            $script:Policy.TargetedUsersToProtect = @('Executive;executive@contoso.com')
            $Result = Invoke-PolicyStandard $Variables

            $Result.Outcome | Should -Be 'Remediated'
            $Result.ExpectedValue.PSObject.Properties.Name | Should -Not -Contain 'targetedUsersToProtect'
            $Result.Diff.Property | Should -Contain 'phishThresholdLevel'
            $Result.Diff.Property | Should -Not -Contain 'targetedUsersToProtect'
            $Write = $script:Sent['Set-AntiPhishPolicy']
            $Write.PhishThresholdLevel | Should -Be 3
            $Write.Keys | Should -Not -Contain 'TargetedUsersToProtect'
        }

        It 'writes all distinct named entries from a tenant list variable and the configured domains once' {
            $Variables = @{
                ImpersonationUserScope   = [PSCustomObject]@{ label = 'Only the users listed'; value = 'Listed' }
                TargetedUsersToProtect   = @([PSCustomObject]@{ label = '%keypeople%'; value = '%keypeople%' }, 'p1@contoso.com')
                TargetedDomainsToProtect = @('Fabrikam.com')
            }
            (Invoke-PolicyStandard $Variables).Outcome | Should -Be 'Remediated'
            $Write = $script:Sent['Set-AntiPhishPolicy']
            $Write.TargetedUsersToProtect | Should -BeExactly @('CEO;ceo@contoso.com', 'Chief Executive;ceo@contoso.com', 'Finance 95% to 100%;finance@contoso.com', 'Person 1;p1@contoso.com')
            $Write.TargetedDomainsToProtect | Should -BeExactly @('fabrikam.com')

            $script:Policy.TargetedUsersToProtect = $Write.TargetedUsersToProtect
            $script:Policy.TargetedDomainsToProtect = $Write.TargetedDomainsToProtect
            $script:Sent.Clear()
            (Invoke-PolicyStandard $Variables).Outcome | Should -Be 'Remediated'
            $script:Sent['Set-AntiPhishPolicy'].Keys | Should -Not -Contain 'TargetedUsersToProtect'
            $script:Sent['Set-AntiPhishPolicy'].Keys | Should -Not -Contain 'TargetedDomainsToProtect'
        }

        It 'writes at both configured caps and stops before writing when either cap is exceeded' {
            $Users = @(foreach ($I in 1..351) { "Person $I;p$([Math]::Min($I, 349))@contoso.com" })
            $Domains = @(foreach ($I in 1..51) { "partner$I.com" })
            $Variables = @{ ImpersonationUserScope = 'Listed'; TargetedUsersToProtect = $Users[0..349]; TargetedDomainsToProtect = $Domains[0..49] }
            (Invoke-PolicyStandard $Variables).Outcome | Should -Be 'Remediated'
            $script:Sent['Set-AntiPhishPolicy'].TargetedUsersToProtect.Count | Should -Be 350
            $script:Sent['Set-AntiPhishPolicy'].TargetedDomainsToProtect.Count | Should -Be 50
            $script:Sent.Clear()

            $Variables.TargetedUsersToProtect = $Users
            (Invoke-PolicyStandard $Variables).Outcome | Should -Be 'Error'
            Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly -ParameterFilter { $Detail -like '*351 distinct user entries*' }
            $Variables.TargetedUsersToProtect = $Users[0..349]
            $Variables.TargetedDomainsToProtect = $Domains
            (Invoke-PolicyStandard $Variables).Outcome | Should -Be 'Error'
            Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly -ParameterFilter { $Detail -like '*51 distinct domains*' }
            $script:Sent.Count | Should -Be 0
        }
    }
}
