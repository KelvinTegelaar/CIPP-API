BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    # The shipped heuristics file is the contract: the weights below must match what the PDF report used.
    $env:CIPPRootPath = $RepoRoot
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecScore.ps1')
    $script:Heuristics = Get-CIPPBecHeuristics

    function New-Results {
        param([hashtable]$Overrides = @{})
        $Base = @{
            ExtractedAt              = '2026-08-20T12:00:00Z'
            AnalysisWindowDays       = 7
            NewRules                 = @()
            InboxRuleChanges         = @()
            MailboxPermissionChanges = @()
            AddedApps                = @()
            MaliciousSPs             = @()
            NewUsers                 = @()
            SafelistChanges          = @()
            SharingChanges           = @()
            SentMessageAnalysis      = [pscustomobject]@{ Flagged = $false }
            MFADevices               = @()
            IntuneDevices            = @()
            LocationAnalysis         = [pscustomobject]@{ ForeignSuccessfulSignInCount = 0; ForeignRuleChangeCount = 0; ForeignSafelistChangeCount = 0; ForeignSharingChangeCount = 0; ForeignSentMessageCount = 0 }
        }
        foreach ($Key in $Overrides.Keys) { $Base[$Key] = $Overrides[$Key] }
        [pscustomobject]$Base
    }
    # a confirmed attacker address with no sign-ins or activity of its own: backs the derived
    # attacker signals without adding AttackerIPs
    $script:Backed = @([pscustomobject]@{ Verdict = 'Compromised'; SuccessfulSignIns = 0; Activities = 0 })
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecScore' {
    It 'scores an empty result as Low with zero and lists every signal unapplied' {
        $Score = Get-CIPPBecScore -Results (New-Results) -Heuristics $script:Heuristics
        $Score.Value | Should -Be 0
        $Score.Level | Should -Be 'Low'
        @($Score.Breakdown | Where-Object { $_.Applied }).Count | Should -Be 0
        $Score.Thresholds.High | Should -Be 7
        $Score.Thresholds.Medium | Should -Be 4
    }

    It 'reproduces the original report weights exactly when every original signal fires' {
        $Results = New-Results @{
            NewRules                 = @([pscustomobject]@{ Name = 'Hide'; MoveToFolder = 'RSS Feeds' })
            InboxRuleChanges         = @([pscustomobject]@{ Operation = 'New-InboxRule' })
            MailboxPermissionChanges = @([pscustomobject]@{ TargetsSuspect = $true }, [pscustomobject]@{ TargetsSuspect = $false })
            AddedApps                = @([pscustomobject]@{ displayName = 'x'; MaliciousMatch = $null })
            MaliciousSPs             = @([pscustomobject]@{ appId = 'a' })
            NewUsers                 = @(1..6 | ForEach-Object { [pscustomobject]@{ id = $_ } })
            SafelistChanges          = @([pscustomobject]@{ Operation = 'Set-MailboxJunkEmailConfiguration' })
            SharingChanges           = @([pscustomobject]@{ Operation = 'AnonymousLinkCreated' })
            SentMessageAnalysis      = [pscustomobject]@{ Flagged = $true }
            MFADevices               = @([pscustomobject]@{ createdDateTime = '2026-08-19T00:00:00Z' })
            IntuneDevices            = @([pscustomobject]@{ enrolledDateTime = '2026-08-18T00:00:00Z' })
            LocationAnalysis         = [pscustomobject]@{ ForeignSuccessfulSignInCount = 2; ForeignRuleChangeCount = 1; ForeignSafelistChangeCount = 0; ForeignSharingChangeCount = 0; ForeignSentMessageCount = 0 }
        }
        $Score = Get-CIPPBecScore -Results $Results -Heuristics $script:Heuristics
        # 3+3+2+1+1+2+5+5+3+3+3+3+2+2 - the PDF's additive score with 'targeting' taking precedence over 'other'
        $Score.Value | Should -Be 38
        $Score.Level | Should -Be 'High'
        ($Score.Breakdown | Where-Object { $_.Signal -eq 'PermissionChanges' }).Applied | Should -BeFalse
        ($Score.Breakdown | Where-Object { $_.Signal -eq 'PermissionChangesTargetingUser' }).Applied | Should -BeTrue
    }

    It 'gives unrelated tenant permission churn +1 and a change targeting the mailbox +2, never both' {
        $Other = Get-CIPPBecScore -Results (New-Results @{ MailboxPermissionChanges = @([pscustomobject]@{ TargetsSuspect = $false }) }) -Heuristics $script:Heuristics
        $Other.Value | Should -Be 1
        $Target = Get-CIPPBecScore -Results (New-Results @{ MailboxPermissionChanges = @([pscustomobject]@{ TargetsSuspect = $true }, [pscustomobject]@{ TargetsSuspect = $false }) }) -Heuristics $script:Heuristics
        $Target.Value | Should -Be 2
    }

    It 'only counts new users above the threshold' {
        $Five = Get-CIPPBecScore -Results (New-Results @{ NewUsers = @(1..5 | ForEach-Object { [pscustomobject]@{ id = $_ } }) }) -Heuristics $script:Heuristics
        $Five.Value | Should -Be 0
        $Six = Get-CIPPBecScore -Results (New-Results @{ NewUsers = @(1..6 | ForEach-Object { [pscustomobject]@{ id = $_ } }) }) -Heuristics $script:Heuristics
        $Six.Value | Should -Be 1
    }

    It 'ignores MFA methods and Intune devices registered before the window' {
        $Results = New-Results @{
            MFADevices    = @([pscustomobject]@{ createdDateTime = '2026-08-01T00:00:00Z' })
            IntuneDevices = @([pscustomobject]@{ enrolledDateTime = '2026-07-01T00:00:00Z' })
        }
        (Get-CIPPBecScore -Results $Results -Heuristics $script:Heuristics).Value | Should -Be 0
    }

    It 'applies the thresholds: 4 is Medium, 7 is High, 3 is Low' {
        # rules(3) + anonymous link(3) = 6... use perm change other (1) + rules (3) = 4
        (Get-CIPPBecScore -Results (New-Results @{ NewRules = @([pscustomobject]@{ Name = 'a' }); MailboxPermissionChanges = @([pscustomobject]@{ TargetsSuspect = $false }) }) -Heuristics $script:Heuristics).Level | Should -Be 'Medium'
        (Get-CIPPBecScore -Results (New-Results @{ NewRules = @([pscustomobject]@{ Name = 'a' }) }) -Heuristics $script:Heuristics).Level | Should -Be 'Low'
        (Get-CIPPBecScore -Results (New-Results @{ NewRules = @([pscustomobject]@{ Name = 'a' }); InboxRuleChanges = @([pscustomobject]@{ Operation = 'x' }); MailboxPermissionChanges = @([pscustomobject]@{ TargetsSuspect = $false }) }) -Heuristics $script:Heuristics).Level | Should -Be 'High'
    }

    It 'weights the full-scope signals' {
        $Cases = @(
            @{ Key = 'Delegations'; Value = @([pscustomobject]@{ Flagged = $true }, [pscustomobject]@{ Flagged = $false }); Expected = 2; Signal = 'FlaggedDelegations' }
            @{ Key = 'UserGrants'; Value = @([pscustomobject]@{ Risk = 'High' }); Expected = 3; Signal = 'RiskyUserGrants' }
            @{ Key = 'UserGrants'; Value = @([pscustomobject]@{ Risk = 'CatalogMatch' }); Expected = 5; Signal = 'CatalogUserGrants' }
            @{ Key = 'TransportRuleChanges'; Value = @([pscustomobject]@{ Flagged = $true }); Expected = 4; Signal = 'RiskyTransportRuleChanges' }
            @{ Key = 'MailboxAddIns'; Value = @([pscustomobject]@{ Flagged = $true }); Expected = 1; Signal = 'FlaggedMailboxAddIns' }
            @{ Key = 'ReceivedMailFindings'; Value = @([pscustomobject]@{ FindingType = 'PossibleTyposquat' }, [pscustomobject]@{ FindingType = 'SubjectPattern' }); Expected = 3; Signal = 'TyposquatSenders' }
            @{ Key = 'DefenderDetections'; Value = @([pscustomobject]@{ Delivered = $true }); Expected = 3; Signal = 'DefenderDetections' }
            @{ Key = 'DirectoryAudits'; Value = @([pscustomobject]@{ Flagged = $true }); Expected = 2; Signal = 'FlaggedDirectoryAudits' }
            @{ Key = 'RegisteredDevices'; Value = @([pscustomobject]@{ RegisteredInWindow = $true }); Expected = 2; Signal = 'RecentRegisteredDevices' }
            @{ Key = 'NonInteractiveSignIns'; Value = @([pscustomobject]@{ ForeignLocation = $true; Status = 'Success' }, [pscustomobject]@{ ForeignLocation = $true; Status = 'Failed' }); Expected = 3; Signal = 'ForeignNonInteractiveSignIns' }
            @{ Key = 'MailActivitySummary'; Value = [pscustomobject]@{ HardDeleteExceeded = $true }; Expected = 2; Signal = 'SuspiciousMailActivity' }
            @{ Key = 'RiskState'; Value = [pscustomobject]@{ Listed = $true; RiskState = 'atRisk'; RiskLevel = 'high' }; Expected = 4; Signal = 'RiskyUserHigh' }
            @{ Key = 'RiskState'; Value = [pscustomobject]@{ Listed = $true; RiskState = 'atRisk'; RiskLevel = 'medium' }; Expected = 2; Signal = 'RiskyUserMedium' }
            @{ Key = 'RiskState'; Value = [pscustomobject]@{ Listed = $true; RiskState = 'confirmedCompromised'; RiskLevel = 'high' }; Expected = 5; Signal = 'ConfirmedCompromised' }
            # an attacker address that only failed to sign in, or a suspicious one, does not count
            @{ Key = 'IPVerdicts'; Value = @([pscustomobject]@{ Verdict = 'LikelyAttacker'; SuccessfulSignIns = 1; Activities = 0 }, [pscustomobject]@{ Verdict = 'Compromised'; SuccessfulSignIns = 0; Activities = 0 }, [pscustomobject]@{ Verdict = 'Suspicious'; SuccessfulSignIns = 3; Activities = 2 }); Expected = 4; Signal = 'AttackerIPs' }
            # item-level activity counts only from addresses judged the attacker's
            @{ Key = 'AttackerMailActivity'; Value = @([pscustomobject]@{ IPVerdict = 'LikelyAttacker'; MailboxOwner = 'victim@contoso.com' }, [pscustomobject]@{ IPVerdict = 'Unknown'; MailboxOwner = 'victim@contoso.com' }); Expected = 3; Signal = 'AttackerMailAccess'; Backed = $true }
            @{ Key = 'AttackerFileActivity'; Value = @([pscustomobject]@{ IPVerdict = 'Compromised' }); Expected = 2; Signal = 'AttackerFileAccess'; Backed = $true }
            @{ Key = 'FormsActivity'; Value = @([pscustomobject]@{ Flagged = $true; IPVerdict = 'LikelyAttacker' }, [pscustomobject]@{ Flagged = $true; IPVerdict = 'Suspicious' }); Expected = 3; Signal = 'AttackerForms'; Backed = $true }
        )
        foreach ($Case in $Cases) {
            $Payload = @{ $Case.Key = $Case.Value }
            if ($Case.Backed) { $Payload.IPVerdicts = $script:Backed }
            $Score = Get-CIPPBecScore -Results (New-Results $Payload) -Heuristics $script:Heuristics
            $Score.Value | Should -Be $Case.Expected -Because "$($Case.Signal) should add $($Case.Expected)"
            ($Score.Breakdown | Where-Object { $_.Signal -eq $Case.Signal }).Applied | Should -BeTrue -Because "$($Case.Signal) should be applied"
        }
    }

    It 'scores attacker access to another mailbox through delegation on top of the mail access itself' {
        $Mail = @(
            [pscustomobject]@{ IPVerdict = 'LikelyAttacker'; MailboxOwner = 'ceo@contoso.com' }
            [pscustomobject]@{ IPVerdict = 'LikelyAttacker'; MailboxOwner = 'Victim@contoso.com' }
        )
        $Score = Get-CIPPBecScore -Results (New-Results @{ UserPrincipalName = 'victim@contoso.com'; AttackerMailActivity = $Mail; IPVerdicts = $script:Backed }) -Heuristics $script:Heuristics
        ($Score.Breakdown | Where-Object Signal -EQ 'DelegatedMailboxAttackerAccess').Count | Should -Be 1 -Because 'the own mailbox, in any case, is not a delegated one'
        $Score.Value | Should -Be 6
    }

    It 'counts only the other accounts an attacker address reached, not the attempts' {
        $Blast = @([pscustomobject]@{ UserPrincipalName = 'a@contoso.com'; Reached = $true }, [pscustomobject]@{ UserPrincipalName = 'b@contoso.com'; Reached = $false })
        $Score = Get-CIPPBecScore -Results (New-Results @{ BlastRadius = $Blast; IPVerdicts = $script:Backed }) -Heuristics $script:Heuristics
        $Signal = $Score.Breakdown | Where-Object Signal -EQ 'OtherAccountsReached'
        $Signal.Count | Should -Be 1
        $Signal.Applied | Should -BeTrue
        $Signal.Weight | Should -Be 3
    }

    It 'counts one heuristic-only attacker verdict once, not again through everything derived from it' {
        # a Microsoft or user address misjudged on network heuristics alone used to add 4+3+2+3+3 = 15
        $Heuristic = [pscustomobject]@{ Verdict = 'LikelyAttacker'; SuccessfulSignIns = 3; Activities = 5; Reasons = @([pscustomobject]@{ Code = 'HostingOrProxy' }, [pscustomobject]@{ Code = 'Foreign' }, [pscustomobject]@{ Code = 'NewToUser' }) }
        $Payload = @{
            UserPrincipalName    = 'victim@contoso.com'
            IPVerdicts           = @($Heuristic)
            AttackerMailActivity = @([pscustomobject]@{ IPVerdict = 'LikelyAttacker'; MailboxOwner = 'ceo@contoso.com' })
            AttackerFileActivity = @([pscustomobject]@{ IPVerdict = 'LikelyAttacker' })
            BlastRadius          = @([pscustomobject]@{ UserPrincipalName = 'a@contoso.com'; Reached = $true })
        }
        $Score = Get-CIPPBecScore -Results (New-Results $Payload) -Heuristics $script:Heuristics
        $Score.Value | Should -Be 4 -Because 'only AttackerIPs counts'
        $Held = @($Score.Breakdown | Where-Object { $_.Signal -in @('AttackerMailAccess', 'AttackerFileAccess', 'OtherAccountsReached', 'DelegatedMailboxAttackerAccess') })
        @($Held | Where-Object Applied).Count | Should -Be 0
        @($Held | Where-Object { $_.Description -like '*not counted*' }).Count | Should -Be 4 -Because 'each held-back signal says why'

        # the same address behind an attacker action, or rated risky by Entra, backs them
        foreach ($Code in @('FlaggedAction', 'RiskySignIn')) {
            $Payload.IPVerdicts = @([pscustomobject]@{ Verdict = 'LikelyAttacker'; SuccessfulSignIns = 3; Activities = 5; Reasons = @([pscustomobject]@{ Code = $Code }) })
            (Get-CIPPBecScore -Results (New-Results $Payload) -Heuristics $script:Heuristics).Value | Should -Be 15 -Because "$Code corroborates the verdict"
        }
    }

    It 'does not score a Defender detection that was blocked, or a dismissed risky user' {
        (Get-CIPPBecScore -Results (New-Results @{ DefenderDetections = @([pscustomobject]@{ Delivered = $false }) }) -Heuristics $script:Heuristics).Value | Should -Be 0
        (Get-CIPPBecScore -Results (New-Results @{ RiskState = [pscustomobject]@{ Listed = $true; RiskState = 'dismissed'; RiskLevel = 'high' } }) -Heuristics $script:Heuristics).Value | Should -Be 0
    }

    It 'scores an old cached payload that has none of the full-scope keys' {
        $Legacy = [pscustomobject]@{ ExtractedAt = '2026-08-20T12:00:00Z'; NewRules = @([pscustomobject]@{ Name = 'a'; MoveToFolder = 'RSS' }) }
        $Score = Get-CIPPBecScore -Results $Legacy -Heuristics $script:Heuristics
        $Score.Value | Should -Be 8
        $Score.Level | Should -Be 'High'
    }
}
