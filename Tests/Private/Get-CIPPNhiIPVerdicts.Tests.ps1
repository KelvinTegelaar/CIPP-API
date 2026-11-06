BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Resolve-CIPPIPAllowBlockList { param($IPAddress, $Entries) }
    function Test-IpInRange { param($IPAddress, $Range) $false }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/NHI/Get-CIPPNhiIPVerdicts.ps1')
    $script:Heuristics = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'Config/NhiHeuristics.json')) | ConvertFrom-Json

    function script:New-SignIn {
        param($IP, $Count = 10, $Success = 10, $Failed = 0, $Country = 'NL', $ASN = '8075', [string[]]$KeyIds = @('key-old'), [string[]]$Types = @('certificate'), [string[]]$Resources = @('Microsoft Graph'), [string[]]$ErrorCodes = @(), [string[]]$Attached = @())
        [pscustomobject]@{ IP = $IP; Count = $Count; Success = $Success; Failed = $Failed; Country = $Country; City = 'Amsterdam'; ASN = $ASN; KeyIds = $KeyIds; CredentialTypes = $Types; Resources = $Resources; ErrorCodes = $ErrorCodes; AttachedResources = $Attached; First = '2026-11-01T00:00:00Z'; Last = '2026-11-04T00:00:00Z' }
    }
    # the app's 23 days before the window: one Azure address, one certificate, Graph only
    $script:Baseline = [pscustomobject]@{
        Total = 500; IPs = @('20.50.1.10'); ASNs = @([pscustomobject]@{ ASN = '8075'; Count = 500 }); Countries = @('NL')
        KeyIds = @('key-old'); CredentialTypes = @('certificate'); Resources = @('Microsoft Graph'); AttachedResources = @()
    }
    $script:Hosting = @{ Hosting = $true; Proxy = $false; ASName = 'Microsoft Corporation' }
}

Describe 'Get-CIPPNhiIPVerdicts' {
    It 'judges the app''s own address and network Expected' {
        $Verdicts = @(Get-CIPPNhiIPVerdicts -SignIns @((script:New-SignIn '20.50.1.10'), (script:New-SignIn '20.50.1.77')) -Baseline $script:Baseline -Geo @{ '20.50.1.10' = $script:Hosting; '20.50.1.77' = $script:Hosting } -Heuristics $script:Heuristics)

        ($Verdicts | Where-Object IP -EQ '20.50.1.10').Verdict | Should -BeExactly 'Expected'
        ($Verdicts | Where-Object IP -EQ '20.50.1.10').Reasons.Code | Should -Contain 'BaselineAddress'
        ($Verdicts | Where-Object IP -EQ '20.50.1.77').Reasons.Code | Should -Contain 'BaselineNetwork' -Because 'an app moving within its /24 is the same host pool'
    }

    It 'calls a new network signing in with a flagged credential a likely attacker' {
        $SignIn = script:New-SignIn '198.51.100.7' -ASN '9009' -Country 'RO' -KeyIds @('key-new') -Types @('clientSecret')
        $Verdict = @(Get-CIPPNhiIPVerdicts -SignIns @($SignIn) -Baseline $script:Baseline -Geo @{ '198.51.100.7' = @{ Hosting = $true; Proxy = $false; ASName = 'M247' } } -FlaggedKeyIds @('KEY-NEW') -Heuristics $script:Heuristics)[0]

        $Verdict.Verdict | Should -BeExactly 'LikelyAttacker'
        $Verdict.Reasons.Code | Should -Contain 'FlaggedCredential'
        $Verdict.Reasons.Code | Should -Contain 'NewNetworkConcentrated' -Because 'every baseline sign-in came from one network'
        $Verdict.Reasons.Code | Should -Contain 'CredentialTypeSwitch'
        $Verdict.Reasons.Code | Should -Contain 'NewCountry'
    }

    It 'treats a non-hosting network as odd for an app but not for a managed identity, and a proxy as odd for both' {
        $Residential = @{ Hosting = $false; Proxy = $false; ASName = 'Ziggo' }
        $App = @(Get-CIPPNhiIPVerdicts -SignIns @((script:New-SignIn '20.50.1.10')) -Baseline $script:Baseline -Geo @{ '20.50.1.10' = $Residential } -Heuristics $script:Heuristics)[0]
        $Identity = @(Get-CIPPNhiIPVerdicts -SignIns @((script:New-SignIn '20.50.1.10')) -Baseline $script:Baseline -Geo @{ '20.50.1.10' = $Residential } -ManagedIdentity -Heuristics $script:Heuristics)[0]
        $Proxy = @(Get-CIPPNhiIPVerdicts -SignIns @((script:New-SignIn '20.50.1.10')) -Baseline $script:Baseline -Geo @{ '20.50.1.10' = @{ Hosting = $true; Proxy = $true; ASName = 'VPN Co' } } -ManagedIdentity -Heuristics $script:Heuristics)[0]

        $App.Reasons.Code | Should -Contain 'NotHosting'
        $Identity.Reasons.Code | Should -Not -Contain 'NotHosting'
        $Proxy.Reasons.Code | Should -Contain 'Proxy'
    }

    It 'caps an address with only failed sign-ins at Suspicious, however odd' {
        $SignIn = script:New-SignIn '198.51.100.9' -Success 0 -Failed 40 -ASN '9009' -Country 'RO' -KeyIds @('key-new') -ErrorCodes @('7000215')
        $Verdict = @(Get-CIPPNhiIPVerdicts -SignIns @($SignIn) -Baseline $script:Baseline -Geo @{ '198.51.100.9' = @{ Hosting = $false; Proxy = $true; ASName = 'Tor' } } -Heuristics $script:Heuristics)[0]

        $Verdict.Verdict | Should -BeExactly 'Suspicious'
        $Verdict.Reasons.Code | Should -Contain 'CredentialFailures'
        $Verdict.Reasons.Code | Should -Contain 'OnlyFailed'
        $Verdict.Reasons.Code | Should -Not -Contain 'NewCredential' -Because 'a credential that never signed in is not in use'
    }

    It 'flags a managed identity used by an Azure resource it was never used by' {
        $Baseline = $script:Baseline.PSObject.Copy()
        $Baseline.AttachedResources = @('/subscriptions/s/resourceGroups/rg/providers/Microsoft.Web/sites/app1')
        $SignIn = script:New-SignIn '20.50.1.10' -Attached @('/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm-new')
        $Verdict = @(Get-CIPPNhiIPVerdicts -SignIns @($SignIn) -Baseline $Baseline -Geo @{ '20.50.1.10' = $script:Hosting } -ManagedIdentity -Heuristics $script:Heuristics)[0]

        $Verdict.Reasons.Code | Should -Contain 'NewAttachedResource'
    }

    It 'calls a new address of an app that used only a few Suspicious, even inside the same cloud and country' {
        # an attacker on an Azure machine: same network (AS8075) and country as the app's own host
        $SignIn = script:New-SignIn '20.99.5.5'
        $Stable = @(Get-CIPPNhiIPVerdicts -SignIns @($SignIn) -Baseline $script:Baseline -Geo @{ '20.99.5.5' = $script:Hosting } -Heuristics $script:Heuristics)[0]
        $Stable.Reasons.Code | Should -Be @('NewToStableApp')
        $Stable.Verdict | Should -BeExactly 'Suspicious'

        # the same address against an app that signs in from a large pool
        $Pool = $script:Baseline.PSObject.Copy()
        $Pool.IPs = @(1..40 | ForEach-Object { "20.50.$_.10" })
        $Busy = @(Get-CIPPNhiIPVerdicts -SignIns @($SignIn) -Baseline $Pool -Geo @{ '20.99.5.5' = $script:Hosting } -Heuristics $script:Heuristics)[0]
        $Busy.Reasons.Code | Should -Be @('NewToApp')
        $Busy.Verdict | Should -BeExactly 'Unknown'
    }

    It 'says nothing is new or known without a baseline' {
        $Verdict = @(Get-CIPPNhiIPVerdicts -SignIns @((script:New-SignIn '198.51.100.7' -ASN '9009')) -Baseline $null -Geo @{} -Heuristics $script:Heuristics)[0]

        $Verdict.Reasons.Code | Should -Be @('NoBaseline')
        $Verdict.Verdict | Should -BeExactly 'Unknown'
    }

    It 'lets CIPP''s block list decide, and lowers the technician''s address' {
        Mock Resolve-CIPPIPAllowBlockList { if ($IPAddress -eq '198.51.100.66') { [pscustomobject]@{ Range = '198.51.100.66/32'; Verdict = 'Blocked'; Strength = 'List' } } }
        $Verdicts = @(Get-CIPPNhiIPVerdicts -SignIns @((script:New-SignIn '198.51.100.66'), (script:New-SignIn '192.0.2.5' -ASN '9009')) -Baseline $script:Baseline -Geo @{} -Guidance @([pscustomobject]@{ Range = '198.51.100.66/32'; Strength = 'List'; Verdict = 'Blocked' }) -TechnicianIPs @([pscustomobject]@{ IP = '192.0.2.5'; By = 'tech@msp.com' }) -Heuristics $script:Heuristics)

        $Verdicts[0].IP | Should -BeExactly '198.51.100.66'
        $Verdicts[0].Verdict | Should -BeExactly 'Compromised'
        ($Verdicts | Where-Object IP -EQ '192.0.2.5').Reasons.Code | Should -Contain 'TechnicianAddress'
    }

    It 'judges an address seen only on the app''s activity' {
        $Verdict = @(Get-CIPPNhiIPVerdicts -Events @([pscustomobject]@{ IP = '198.51.100.20'; Count = 300; Kinds = @('Mail') }) -Baseline $script:Baseline -Geo @{ '198.51.100.20' = @{ Hosting = $false; Proxy = $true; ASName = 'VPN Co' } } -Heuristics $script:Heuristics)[0]

        $Verdict.Activities | Should -Be 300
        $Verdict.SignIns | Should -Be 0
        $Verdict.Reasons.Code | Should -Contain 'Proxy'
        $Verdict.Reasons.Code | Should -Not -Contain 'NewToApp' -Because 'only a sign-in proves the app came from there'
    }
}
