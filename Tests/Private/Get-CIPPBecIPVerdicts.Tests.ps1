BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($File in @('Authentication/ConvertTo-CIPPIPRange.ps1', 'Authentication/Test-IpInRange.ps1', 'Authentication/Resolve-CIPPIPAllowBlockList.ps1', 'BEC/ConvertTo-CIPPBecHostAddress.ps1', 'BEC/Get-CIPPBecIPVerdicts.ps1', 'BEC/ConvertTo-CIPPBecIPEvents.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    $script:Heuristics = Get-Content (Join-Path $RepoRoot 'Config/BecHeuristics.json') -Raw | ConvertFrom-Json

    function New-SignIn {
        param($IP, $Status = 'Success', $Country = 'AU', $City = 'Sydney', $ASN = '1221', $Risk = 'none', $UserAgent = 'Mozilla/5.0', $Compliant = $false, $SessionId = $null, $When = '2026-09-20T01:00:00Z')
        [pscustomobject]@{ IPAddress = $IP; Status = $Status; Country = $Country; City = $City; ASN = $ASN; RiskLevelDuringSignIn = $Risk; UserAgent = $UserAgent; DeviceCompliant = $Compliant; SessionId = $SessionId; CreatedDateTime = $When }
    }
    # 40 successful sign-ins before the window, almost all from the office address
    $script:Baseline = [pscustomobject]@{
        Successful = 40
        IPs        = @([pscustomobject]@{ IP = '203.0.113.10'; SignIns = 38; Share = 0.95; Days = 20 }, [pscustomobject]@{ IP = '203.0.113.99'; SignIns = 1; Share = 0.025; Days = 1 })
        ASNs       = @([pscustomobject]@{ ASN = '1221'; SignIns = 40; Share = 1.0 })
        Locations  = @([pscustomobject]@{ Country = 'AU'; City = 'Sydney'; SignIns = 40; Share = 1.0 })
    }
    $script:Geo = @{
        '198.51.100.7' = [pscustomobject]@{ CountryOrRegion = 'NG'; City = 'Lagos'; Proxy = $false; Hosting = $true; ASName = 'DIGITALOCEAN-ASN' }
        '203.0.113.10' = [pscustomobject]@{ CountryOrRegion = 'AU'; City = 'Sydney'; Proxy = $false; Hosting = $false; ASName = 'TELSTRA' }
        '40.107.1.1'   = [pscustomobject]@{ CountryOrRegion = 'US'; City = 'Boydton'; Proxy = $false; Hosting = $true; ASName = 'MICROSOFT-CORP-MSN-AS-BLOCK' }
    }
    function Get-Verdicts {
        param($SignIns = @(), $NonInteractive = @(), $Events = @(), $Guidance = @(), $Overrides = @(), $Peers = @{}, $Baseline = $script:Baseline, $ServiceRanges = @())
        Get-CIPPBecIPVerdicts -SignIns $SignIns -NonInteractiveSignIns $NonInteractive -Events $Events -Baseline $Baseline -Guidance $Guidance -Overrides $Overrides -Peers $Peers -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -ServiceRanges $ServiceRanges
    }
    function Get-Row { param($Rows, $IP) $Rows | Where-Object IP -EQ $IP }
}

Describe 'Get-CIPPBecIPVerdicts' {
    It 'calls a new foreign hosting address behind a flagged inbox rule a likely attacker, with its reasons' {
        $Rows = Get-Verdicts -SignIns @(New-SignIn -IP '198.51.100.7' -Country 'NG' -City 'Lagos' -ASN '14061') -Events @([pscustomobject]@{ IP = '198.51.100.7:51234'; Kind = 'Inbox rule change'; Flagged = $true; ActorKind = 'User'; When = '2026-09-20T01:05:00Z' })
        $Row = Get-Row $Rows '198.51.100.7'
        $Row.Verdict | Should -Be 'LikelyAttacker'
        @($Row.Reasons.Code) | Should -Contain 'FlaggedAction'
        @($Row.Reasons.Code) | Should -Contain 'HostingOrProxy'
        @($Row.Reasons.Code) | Should -Contain 'Foreign'
        @($Row.Reasons.Code) | Should -Contain 'NewToUser'
        $Row.Kinds | Should -Be @('Inbox rule change')
        $Row.Activities | Should -Be 1 -Because 'the ported audit address is the same host as the sign-in'
    }

    It 'calls the regular office address, network and city of the user a likely user' {
        $Row = Get-Row (Get-Verdicts -SignIns @(New-SignIn -IP '203.0.113.10' -Compliant $true)) '203.0.113.10'
        $Row.Verdict | Should -Be 'LikelyUser'
        @($Row.Reasons.Code) | Should -Contain 'BaselineRegular'
        @($Row.Reasons.Code) | Should -Contain 'CompliantDevice'
        $Row.BaselineShare | Should -Be 0.95
    }

    It 'lets an investigator override decide, down to a CIDR range' {
        $Rows = Get-Verdicts -SignIns @(New-SignIn -IP '203.0.113.10') -Overrides @([pscustomobject]@{ Range = '203.0.113.0/24'; Verdict = 'Compromised'; Note = 'token theft on the office NAT' })
        $Row = Get-Row $Rows '203.0.113.10'
        $Row.Verdict | Should -Be 'Compromised'
        $Row.Source | Should -Match 'Investigator \(203\.0\.113\.0/24\): token theft'
    }

    It 'follows the CIPP list, where a tenant allow relaxes an AllTenants block' {
        $Guidance = @(
            [pscustomobject]@{ Range = '198.51.100.0/24'; Prefix = 24; Verdict = 'Blocked'; Strength = 'List'; Source = 'CIPP IP list (all tenants)'; Scope = 'AllTenants' }
            [pscustomobject]@{ Range = '198.51.100.0/24'; Prefix = 24; Verdict = 'Trusted'; Strength = 'List'; Source = 'CIPP IP list (this tenant)'; Scope = 'Tenant' }
        )
        $Row = Get-Row (Get-Verdicts -SignIns @(New-SignIn -IP '198.51.100.7' -Country 'NG') -Guidance $Guidance) '198.51.100.7'
        $Row.Verdict | Should -Be 'Safe'
        $Row.Source | Should -Match 'this tenant'
    }

    It 'treats a Microsoft address with no sign-ins as a service, but scores one the user signed in from' {
        $Service = Get-Row (Get-Verdicts -Events @([pscustomobject]@{ IP = '40.107.1.1'; Kind = 'Mailbox MailItemsAccessed'; Flagged = $false; ActorKind = 'User' })) '40.107.1.1'
        $Service.Verdict | Should -Be 'Service'
        $Rented = Get-Row (Get-Verdicts -SignIns @(New-SignIn -IP '40.107.1.1' -Country 'US' -ASN '8075')) '40.107.1.1'
        $Rented.Verdict | Should -Not -Be 'Service'
        @($Rented.Reasons.Code) | Should -Contain 'HostingOrProxy'
    }

    It 'classes an address in the Microsoft 365 ranges as a service even when the user signed in from it' {
        # the shape that used to snowball: a Microsoft front end in the user's non-interactive sign-ins,
        # hosting + foreign + new to the user = LikelyAttacker on heuristics alone
        $Ranges = @('40.107.0.0/16', '2603:1006::/40', '2603:1036::/36')
        $NonInteractive = @(
            New-SignIn -IP '2603:1036:303:2c50::5' -Country 'US' -City 'Boydton' -ASN '8075'
            New-SignIn -IP '40.107.1.1' -Country 'US' -City 'Boydton' -ASN '8075'
        )
        $Rows = Get-Verdicts -NonInteractive $NonInteractive -ServiceRanges $Ranges
        foreach ($IP in @('2603:1036:303:2c50::5', '40.107.1.1')) {
            $Row = Get-Row $Rows $IP
            $Row.Verdict | Should -Be 'Service' -Because "$IP is a Microsoft 365 front end"
            $Row.Source | Should -Match 'Microsoft 365 service address'
        }
        (Get-Row (Get-Verdicts -NonInteractive $NonInteractive) '40.107.1.1').Verdict | Should -Not -Be 'Service' -Because 'without the list a signed-in Microsoft address is still judged (rented Azure)'
        $Rented = Get-Row (Get-Verdicts -SignIns @(New-SignIn -IP '20.55.1.1' -Country 'US' -ASN '8075') -ServiceRanges $Ranges) '20.55.1.1'
        $Rented.Verdict | Should -Not -Be 'Service' -Because 'Azure compute outside the Microsoft 365 ranges can be the attacker'
    }

    It 'knows a new IPv6 privacy address by the /64 the user signed in from before the window' {
        $Baseline = [pscustomobject]@{
            Successful = 40
            # a device rotating through temporary addresses: every one seen on a day or two
            IPs        = @(1..8 | ForEach-Object { [pscustomobject]@{ IP = "2001:db8:1:2:a:b:c:$_"; SignIns = 5; Share = 0.125; Days = 1 } })
            ASNs       = @([pscustomobject]@{ ASN = '1221'; SignIns = 40; Share = 1.0 })
            Locations  = @([pscustomobject]@{ Country = 'AU'; City = 'Sydney'; SignIns = 40; Share = 1.0 })
        }
        $Rows = Get-Verdicts -SignIns @((New-SignIn -IP '2001:db8:1:2:dead:beef:0:1'), (New-SignIn -IP '2001:db8:9:9::1')) -Baseline $Baseline
        $HomeRow = Get-Row $Rows '2001:db8:1:2:dead:beef:0:1'
        @($HomeRow.Reasons.Code) | Should -Contain 'BaselineRegular'
        @($HomeRow.Reasons.Code) | Should -Not -Contain 'NewToUser'
        ($HomeRow.Reasons | Where-Object Code -EQ 'BaselineRegular').Text | Should -Match '2001:db8:1:2::/64'
        $HomeRow.Verdict | Should -Be 'LikelyUser'
        @((Get-Row $Rows '2001:db8:9:9::1').Reasons.Code) | Should -Contain 'NewToUser' -Because 'another /64 is still new'
    }

    It 'never lifts an address the user used before the window through a shared session' {
        # one dual-stack device: its IPv4 and IPv6 addresses carry the same Entra session
        $Baseline = [pscustomobject]@{
            Successful = 40
            IPs        = @([pscustomobject]@{ IP = '203.0.113.99'; SignIns = 1; Share = 0.025; Days = 1 })
            ASNs       = @([pscustomobject]@{ ASN = '1221'; SignIns = 40; Share = 1.0 })
            Locations  = @([pscustomobject]@{ Country = 'AU'; City = 'Sydney'; SignIns = 40; Share = 1.0 })
        }
        $SignIns = @(
            New-SignIn -IP '198.51.100.7' -Country 'NG' -Risk 'high' -SessionId 'S1'
            New-SignIn -IP '203.0.113.99' -SessionId 'S1'
        )
        $Rows = Get-Verdicts -SignIns $SignIns -Baseline $Baseline -Events @([pscustomobject]@{ IP = '198.51.100.7'; Kind = 'Directory change'; Flagged = $true })
        (Get-Row $Rows '198.51.100.7').Verdict | Should -Be 'LikelyAttacker'
        @((Get-Row $Rows '203.0.113.99').Reasons.Code) | Should -Not -Contain 'SharedSession'
    }

    It 'never calls an address with only failed sign-ins more than suspicious' {
        $SignIns = @(1..5 | ForEach-Object { New-SignIn -IP '198.51.100.7' -Status 'Failed' -Country 'NG' -Risk 'high' })
        $Row = Get-Row (Get-Verdicts -SignIns $SignIns) '198.51.100.7'
        $Row.Verdict | Should -Be 'Suspicious'
        @($Row.Reasons.Code) | Should -Contain 'OnlyFailed'
    }

    It 'lifts an unknown address that shares an Entra session with a likely-attacker address' {
        $SignIns = @(
            New-SignIn -IP '198.51.100.7' -Country 'NG' -Risk 'high' -SessionId 'S1'
            New-SignIn -IP '192.0.2.44' -Country 'AU' -City 'Sydney' -SessionId 'S1'
        )
        $Rows = Get-Verdicts -SignIns $SignIns -Events @([pscustomobject]@{ IP = '198.51.100.7'; Kind = 'Directory change'; Flagged = $true })
        (Get-Row $Rows '198.51.100.7').Verdict | Should -Be 'LikelyAttacker'
        $Lifted = Get-Row $Rows '192.0.2.44'
        @($Lifted.Reasons.Code) | Should -Contain 'SharedSession'
        $Lifted.Verdict | Should -BeIn @('Suspicious', 'LikelyAttacker')
    }

    It 'reads colleagues before the window as an office exit, and newcomers only in the window as a wider attack' {
        $Peers = @{
            '192.0.2.10' = [pscustomobject]@{ OtherUsersBefore = 12; OtherUsersInWindowOnly = 0; Users = @('a@contoso.com') }
            '192.0.2.20' = [pscustomobject]@{ OtherUsersBefore = 0; OtherUsersInWindowOnly = 3; Users = @('b@contoso.com', 'c@contoso.com', 'd@contoso.com') }
        }
        $Rows = Get-Verdicts -SignIns @((New-SignIn -IP '192.0.2.10'), (New-SignIn -IP '192.0.2.20')) -Peers $Peers
        @((Get-Row $Rows '192.0.2.10').Reasons.Code) | Should -Contain 'Colleagues'
        @((Get-Row $Rows '192.0.2.20').Reasons.Code) | Should -Contain 'WiderAttack'
        (Get-Row $Rows '192.0.2.20').OtherUsers.Count | Should -Be 3
    }

    It 'weighs a trusted named location strongly and exchange list entries lightly' {
        $Guidance = @(
            [pscustomobject]@{ Range = '192.0.2.0/24'; Prefix = 24; Verdict = 'Trusted'; Strength = 'Hint'; Source = "Trusted named location 'HQ'" }
            [pscustomobject]@{ Range = '192.0.2.50'; Prefix = 32; Verdict = 'Blocked'; Strength = 'Hint'; Source = 'Tenant allow/block list (Block)' }
        )
        $Rows = Get-Verdicts -SignIns @((New-SignIn -IP '192.0.2.10'), (New-SignIn -IP '192.0.2.50')) -Guidance $Guidance
        ((Get-Row $Rows '192.0.2.10').Reasons | Where-Object Code -EQ 'AllowHint').Weight | Should -Be -4
        ((Get-Row $Rows '192.0.2.50').Reasons | Where-Object Code -EQ 'BlockHint').Weight | Should -Be 2
    }

    It "classes an address whose sign-ins are all the CIPP application's own as a service" {
        $SignIns = @(1..3 | ForEach-Object { $S = New-SignIn -IP '135.119.241.152' -Status 'Failed' -Country 'US'; $S | Add-Member -NotePropertyName AppId -NotePropertyValue 'cipp-app'; $S })
        $Rows = Get-CIPPBecIPVerdicts -NonInteractiveSignIns $SignIns -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -CippAppId 'cipp-app'
        $Row = Get-Row $Rows '135.119.241.152'
        $Row.Verdict | Should -Be 'Service'
        $Row.Source | Should -Match 'CIPP or partner delegated administration'
        $Mixed = @($SignIns) + @(New-SignIn -IP '135.119.241.152' -Country 'US')
        (Get-Row (Get-CIPPBecIPVerdicts -NonInteractiveSignIns $Mixed -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -CippAppId 'cipp-app') '135.119.241.152').Verdict | Should -Not -Be 'Service' -Because 'a sign-in by anything else there is judged'
        # Microsoft's Partner Customer Delegated Administration app (GDAP) is a service app out of the box
        $Gdap = @(1..2 | ForEach-Object { $S = New-SignIn -IP '135.119.241.153' -Status 'Failed' -Country 'US'; $S | Add-Member -NotePropertyName AppId -NotePropertyValue '2832473f-ec63-45fb-976f-5d45a7d4bb91'; $S })
        (Get-Row (Get-CIPPBecIPVerdicts -NonInteractiveSignIns $Gdap -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -CippAppId 'cipp-app') '135.119.241.153').Verdict | Should -Be 'Service'
    }

    It 'gives the address of the technician who ran the case a trusted start, but still judges it' {
        $Tech = @([pscustomobject]@{ IP = '192.0.2.77'; By = 'tech@msp.com' })
        $AtHome = Get-Row (Get-CIPPBecIPVerdicts -SignIns @(New-SignIn -IP '192.0.2.77:50000' -Country 'AU') -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -TechnicianIPs $Tech) '192.0.2.77'
        $AtHome.Verdict | Should -Be 'LikelyUser'
        $AtHome.Source | Should -Be 'Heuristics'
        ($AtHome.Reasons | Where-Object Code -EQ 'TechnicianAddress').Text | Should -Match 'tech@msp.com'
        $SignIns = @(New-SignIn -IP '192.0.2.77:50000' -Country 'NG')
        $Row = Get-Row (Get-CIPPBecIPVerdicts -SignIns $SignIns -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -TechnicianIPs $Tech) '192.0.2.77'
        $Row.Verdict | Should -Not -Be 'Service' -Because 'a technician address is a head start, not a pass'
        $Row.Score | Should -BeLessThan (Get-Row (Get-CIPPBecIPVerdicts -SignIns $SignIns -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics) '192.0.2.77').Score
        $Overridden = Get-CIPPBecIPVerdicts -SignIns $SignIns -Baseline $script:Baseline -Geo $script:Geo -UsageLocation 'AU' -Heuristics $script:Heuristics -TechnicianIPs $Tech -Overrides @([pscustomobject]@{ Range = '192.0.2.77'; Verdict = 'Compromised' })
        (Get-Row $Overridden '192.0.2.77').Verdict | Should -Be 'Compromised' -Because 'an investigator decision still wins'
    }

    It 'classes an address seen only on CIPP or partner actions as a service' {
        $Row = Get-Row (Get-Verdicts -Events @([pscustomobject]@{ IP = '20.1.2.3'; Kind = 'Mailbox permission change'; Flagged = $true; ActorKind = 'CIPP' })) '20.1.2.3'
        $Row.Verdict | Should -Be 'Service'
    }

    It 'judges nothing as new against an empty baseline and sorts the worst first' {
        $Rows = Get-Verdicts -Baseline $null -SignIns @((New-SignIn -IP '192.0.2.10'), (New-SignIn -IP '198.51.100.7' -Country 'NG'))
        @((Get-Row $Rows '192.0.2.10').Reasons.Code) | Should -Not -Contain 'NewToUser'
        $Rows[0].IP | Should -Be '198.51.100.7'
    }
}

Describe 'ConvertTo-CIPPBecIPEvents' {
    It 'keeps only the actions of this account from the tenant-wide sections and flags the attacker ones' {
        $Results = [pscustomobject]@{
            NewRules                 = @([pscustomobject]@{ Name = 'Hide'; Suspicious = $true })
            InboxRuleChanges         = @([pscustomobject]@{ ClientIP = '198.51.100.7'; RuleName = 'victim\Hide'; Date = 'x'; Operation = 'New-InboxRule' })
            MailboxPermissionChanges = @(
                [pscustomobject]@{ ClientIP = '198.51.100.7'; UserId = 'victim@contoso.com'; TargetsSuspect = $true }
                [pscustomobject]@{ ClientIP = '10.9.9.9'; UserId = 'admin@contoso.com'; TargetsSuspect = $true }
            )
            TransportRuleChanges     = @([pscustomobject]@{ ClientIP = '10.9.9.9'; Actor = 'admin@contoso.com'; Flagged = $true })
            SharingChanges           = @([pscustomobject]@{ ClientIP = '198.51.100.7'; Operation = 'AnonymousLinkCreated' }, [pscustomobject]@{ ClientIP = '203.0.113.10'; Operation = 'SecureLinkCreated' })
            SentMessages             = @([pscustomobject]@{ FromIP = '198.51.100.7'; Received = 'y' })
            SentMessageAnalysis      = [pscustomobject]@{ Flagged = $true }
            MailActivity             = @([pscustomobject]@{ ClientIP = '203.0.113.10'; Operation = 'MailItemsAccessed'; FirstSeen = 'z'; SessionIds = @('M1', 'M2') })
        }
        $Events = ConvertTo-CIPPBecIPEvents -Results $Results -UserPrincipalName 'Victim@contoso.com'
        @($Events | Where-Object IP -EQ '10.9.9.9').Count | Should -Be 0 -Because 'the address of another admin says nothing about this account'
        @($Events | Where-Object { $_.IP -eq '198.51.100.7' -and $_.Flagged }).Kind | Should -Be @('Inbox rule change', 'Mailbox permission change', 'Sharing change', 'Sent mail')
        ($Events | Where-Object Kind -EQ 'Mailbox MailItemsAccessed').SessionIds | Should -Be @('M1', 'M2')
        ($Events | Where-Object { $_.Kind -eq 'Sharing change' -and $_.IP -eq '203.0.113.10' }).Flagged | Should -BeFalse
    }
}
