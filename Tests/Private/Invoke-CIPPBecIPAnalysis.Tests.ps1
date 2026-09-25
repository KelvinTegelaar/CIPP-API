BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPBecIPGuidance { param($TenantFilter, $Anchor) }
    function Get-CIPPBecSignInBaseline { param($TenantFilter, $UserId, $StartDate, $EndDate) }
    function Get-CIPPBecIPPeers { param($TenantFilter, $UserId, $IPs, $StartDate, $WindowStart) }
    function Get-CIPPBecColleagueSample { param($TenantFilter, $ExcludeUserId, $StartDate, $Count) }
    function Get-CIPPBecCorrelatedUserPeers { param($TenantFilter, $UserIds, $IPs, $StartDate, $WindowStart) }
    function Get-CIPPGeoIPLocationBatch { param([string[]]$IPs) }
    function Get-NormalizedError { param($message) $message }
    foreach ($File in @('Authentication/ConvertTo-CIPPIPRange.ps1', 'Authentication/Test-IpInRange.ps1', 'Authentication/Resolve-CIPPIPAllowBlockList.ps1', 'BEC/ConvertTo-CIPPBecHostAddress.ps1', 'BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Get-CIPPBecIPVerdicts.ps1', 'BEC/ConvertTo-CIPPBecIPEvents.ps1', 'BEC/Invoke-CIPPBecIPAnalysis.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    $script:Heuristics = Get-Content (Join-Path $RepoRoot 'Config/BecHeuristics.json') -Raw | ConvertFrom-Json
    $script:Results = [pscustomobject]@{
        SuspectUserSignIns    = @(
            [pscustomobject]@{ IPAddress = '203.0.113.10'; Status = 'Success'; Country = 'AU'; City = 'Sydney'; ASN = '1221'; CreatedDateTime = '2026-09-20T01:00:00Z' }
            [pscustomobject]@{ IPAddress = '198.51.100.7'; Status = 'Success'; Country = 'NG'; City = 'Lagos'; ASN = '14061'; CreatedDateTime = '2026-09-20T02:00:00Z' }
        )
        NonInteractiveSignIns = @()
        InboxRuleChanges      = @([pscustomobject]@{ ClientIP = '198.51.100.7'; RuleName = 'Hide'; Date = '2026-09-20T02:05:00Z' })
        NewRules              = @([pscustomobject]@{ Name = 'Hide'; Suspicious = $true })
    }
    $script:Baseline = [pscustomobject]@{ Successful = 30; IPs = @([pscustomobject]@{ IP = '203.0.113.10'; SignIns = 30; Share = 1.0; Days = 15 }); ASNs = @([pscustomobject]@{ ASN = '1221'; Share = 1.0 }); Locations = @([pscustomobject]@{ Country = 'AU'; City = 'Sydney'; Share = 1.0 }) }
    function Invoke-Analysis { param([hashtable]$Extra = @{}) Invoke-CIPPBecIPAnalysis -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -Results $script:Results -Heuristics $script:Heuristics -WindowStart ([datetime]'2026-09-16') -UsageLocation 'AU' @Extra }
}

Describe 'Invoke-CIPPBecIPAnalysis' {
    BeforeEach {
        Mock Get-CIPPBecIPGuidance { New-CIPPBecCollectorResult -Data @() }
        Mock Get-CIPPBecSignInBaseline { New-CIPPBecCollectorResult -Data $script:Baseline -Count 30 }
        Mock Get-CIPPGeoIPLocationBatch { @{ '198.51.100.7' = [pscustomobject]@{ CountryOrRegion = 'NG'; City = 'Lagos'; Hosting = $true; Proxy = $false; ASName = 'DIGITALOCEAN-ASN' } } }
        Mock Get-CIPPBecIPPeers { $R = @{}; foreach ($IP in $IPs) { $R[$IP] = [pscustomobject]@{ IP = $IP; OtherUsersBefore = 0; OtherUsersInWindowOnly = 2; Users = @('x@contoso.com', 'y@contoso.com') } }; $R }
    }

    It 'looks up other accounts only for addresses that are not already settled, and judges with them' {
        $Analysis = Invoke-Analysis
        Should -Invoke Get-CIPPBecIPPeers -Times 1 -ParameterFilter { @($IPs) -contains '198.51.100.7' -and @($IPs) -notcontains '203.0.113.10' }
        ($Analysis.Verdicts | Where-Object IP -EQ '198.51.100.7').Verdict | Should -Be 'LikelyAttacker'
        @(($Analysis.Verdicts | Where-Object IP -EQ '198.51.100.7').Reasons.Code) | Should -Contain 'WiderAttack'
        ($Analysis.Verdicts | Where-Object IP -EQ '203.0.113.10').Verdict | Should -Be 'LikelyUser'
        $Analysis.Baseline.Complete | Should -BeTrue
        $Analysis.PeersResult.Complete | Should -BeTrue
    }

    It 're-uses the stored baseline and peers of the case instead of fetching them again' {
        $Known = @([pscustomobject]@{ IP = '198.51.100.7'; OtherUsersBefore = 0; OtherUsersInWindowOnly = 0; Users = @() })
        $null = Invoke-Analysis -Extra @{ Baseline = $script:Baseline; KnownPeers = $Known }
        Should -Invoke Get-CIPPBecSignInBaseline -Times 0
        Should -Invoke Get-CIPPBecIPPeers -Times 0
    }

    It 'merges the evidence of correlated users into the tenant-wide peers' {
        $Extra = @{ '198.51.100.7' = [pscustomobject]@{ IP = '198.51.100.7'; OtherUsersBefore = 3; OtherUsersInWindowOnly = 0; Users = @('colleague@contoso.com') } }
        $Analysis = Invoke-Analysis -Extra @{ ExtraPeers = $Extra }
        $Peer = $Analysis.Peers['198.51.100.7']
        $Peer.OtherUsersBefore | Should -Be 3
        $Peer.Users | Should -Contain 'colleague@contoso.com'
        $Peer.Users | Should -Contain 'x@contoso.com'
    }

    It 'samples colleagues only when asked, and never counts the same colleague twice' {
        Mock Get-CIPPBecColleagueSample { @('c1', 'c2') }
        Mock Get-CIPPBecCorrelatedUserPeers { @{ '198.51.100.7' = [pscustomobject]@{ IP = '198.51.100.7'; OtherUsersBefore = 1; OtherUsersInWindowOnly = 2; Users = @('x@contoso.com') } } }
        $null = Invoke-Analysis
        Should -Invoke Get-CIPPBecColleagueSample -Times 0
        $Analysis = Invoke-Analysis -Extra @{ SampleColleagues = $true }
        Should -Invoke Get-CIPPBecCorrelatedUserPeers -Times 1 -ParameterFilter { @($UserIds) -join ',' -eq 'c1,c2' -and @($IPs) -contains '198.51.100.7' }
        $Peer = $Analysis.Peers['198.51.100.7']
        $Peer.OtherUsersInWindowOnly | Should -Be 2 -Because 'x@contoso.com is found by both lookups'
        $Peer.OtherUsersBefore | Should -Be 1
    }

    It 'still judges from what it has when the baseline and peer lookups fail' {
        Mock Get-CIPPBecSignInBaseline { throw 'Graph 429' }
        Mock Get-CIPPBecIPPeers { throw 'Graph 503' }
        $Analysis = Invoke-Analysis
        $Analysis.Baseline.Error | Should -Match 'Graph 429'
        $Analysis.PeersResult.Error | Should -Match 'Graph 503'
        @($Analysis.Verdicts).Count | Should -Be 2
    }
}
