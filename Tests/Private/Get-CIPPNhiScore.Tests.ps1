BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/NHI/Get-CIPPNhiScore.ps1')
    # The shipped heuristics file is the contract.
    $script:Heuristics = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'Config/NhiHeuristics.json')) | ConvertFrom-Json
    $script:Start = '2026-10-29T12:00:00Z'

    function New-Results {
        param([hashtable]$Overrides = @{})
        $Base = @{
            StartDate     = $script:Start
            BaselineDays  = 23
            Exposure      = [pscustomobject]@{ HighestImpact = 'High'; CredentialDetails = @(); IsMicrosoftApp = $false; IsCippApp = $false; ServicePrincipalCredentialCount = 0 }
            Baseline      = [pscustomobject]@{ Total = 500; KeyIds = @('key-old'); Resources = @('Microsoft Graph'); AttachedResources = @() }
            SignInSummary = [pscustomobject]@{ Total = 100; Success = 100; Resources = @('Microsoft Graph'); AttachedResources = @() }
            IPVerdicts    = @()
            Changes       = @()
            Consents      = @()
            FlaggedKeyIds = @()
        }
        foreach ($Key in $Overrides.Keys) { $Base[$Key] = $Overrides[$Key] }
        [pscustomobject]$Base
    }
    $script:Attacker = [pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'LikelyAttacker'; SuccessfulSignIns = 4; Activities = 0; Reasons = @([pscustomobject]@{ Code = 'NewNetwork' }) }
}

Describe 'Get-CIPPNhiScore' {
    It 'scores a quiet app Low with every signal listed and unapplied' {
        $Score = Get-CIPPNhiScore -Results (New-Results) -Heuristics $script:Heuristics

        $Score.Value | Should -Be 0
        $Score.EvidenceLevel | Should -BeExactly 'Low'
        $Score.Level | Should -BeExactly 'Low'
        @($Score.Breakdown | Where-Object Applied).Count | Should -Be 0
        @($Score.Breakdown).Count | Should -Be @($script:Heuristics.score.weights.PSObject.Properties).Count -Because 'every weighted signal has a breakdown row'
    }

    It 'adds a flagged credential added in the window, signing in from an attacker address' {
        $Results = New-Results @{
            Exposure            = [pscustomobject]@{ HighestImpact = 'Critical'; CredentialDetails = @([pscustomobject]@{ KeyId = 'key-new'; Purpose = 'Sign-in'; Expired = $false; AddedDateTime = '2026-11-01T00:00:00Z'; Flags = @('AddedRecently', 'AddedByApp') }) }
            FlaggedKeyIds       = @('key-new')
            SignInsByCredential = @([pscustomobject]@{ KeyId = 'key-new'; Success = 4 })
            IPVerdicts          = @($script:Attacker)
        }
        $Score = Get-CIPPNhiScore -Results $Results -Heuristics $script:Heuristics
        $Applied = @($Score.Breakdown | Where-Object Applied).Signal

        $Applied | Should -Be @('CredentialAdded', 'CredentialAddedByApp', 'AttackerIPs', 'FlaggedCredentialUsed')
        $Score.Value | Should -Be (2 + 3 + 4 + 4)
        $Score.EvidenceLevel | Should -BeExactly 'High'
        $Score.Impact | Should -BeExactly 'Critical'
        $Score.Level | Should -BeExactly 'Critical'
        ($Score.Breakdown | Where-Object Signal -EQ 'NewCredentialInUse').Applied | Should -BeFalse -Because 'a flagged credential is counted once'
    }

    It 'crosses the evidence with the impact of the app''s access' {
        $Evidence = @{ RogueMatch = [pscustomobject]@{ Name = 'Bad' }; IPVerdicts = @($script:Attacker) }
        foreach ($Case in @(
                @{ Impact = 'Low'; Level = 'Medium' }
                @{ Impact = 'High'; Level = 'Critical' }
            )) {
            $Results = New-Results ($Evidence + @{ Exposure = [pscustomobject]@{ HighestImpact = $Case.Impact; CredentialDetails = @() } })
            (Get-CIPPNhiScore -Results $Results -Heuristics $script:Heuristics).Level | Should -BeExactly $Case.Level
        }
        $NoExposure = New-Results ($Evidence + @{ Exposure = $null })
        $Score = Get-CIPPNhiScore -Results $NoExposure -Heuristics $script:Heuristics
        $Score.Impact | Should -BeExactly 'Medium' -Because 'unknown reach is never rated harmless'
        $Score.ImpactKnown | Should -BeFalse
        $Uncatalogued = New-Results ($Evidence + @{ Exposure = [pscustomobject]@{ HighestImpact = $null; CredentialDetails = @() } })
        (Get-CIPPNhiScore -Results $Uncatalogued -Heuristics $script:Heuristics).Impact | Should -BeExactly 'Low'
    }

    It 'counts mail and file activity from an attacker address only when the address is corroborated' {
        $Workload = [pscustomobject]@{ ByIP = @([pscustomobject]@{ IP = '198.51.100.7'; Count = 50 }) }
        $Plain = Get-CIPPNhiScore -Results (New-Results @{ IPVerdicts = @($script:Attacker); WorkloadActivity = $Workload }) -Heuristics $script:Heuristics
        ($Plain.Breakdown | Where-Object Signal -EQ 'AttackerWorkload').Applied | Should -BeFalse
        ($Plain.Breakdown | Where-Object Signal -EQ 'AttackerWorkload').Description | Should -BeLike '*not counted*'

        $Backed = $script:Attacker.PSObject.Copy()
        $Backed.Reasons = @([pscustomobject]@{ Code = 'FlaggedCredential' })
        $Corroborated = Get-CIPPNhiScore -Results (New-Results @{ IPVerdicts = @($Backed); WorkloadActivity = $Workload }) -Heuristics $script:Heuristics
        ($Corroborated.Breakdown | Where-Object Signal -EQ 'AttackerWorkload').Applied | Should -BeTrue
    }

    It 'applies the count thresholds for consent bursts, mailboxes and files' {
        $Consents = @(1..3 | ForEach-Object { [pscustomobject]@{ ActivityDateTime = '2026-11-02T00:00:00Z'; User = "u$_@contoso.com" } })
        $Score = Get-CIPPNhiScore -Results (New-Results @{ Consents = $Consents; WorkloadSummary = [pscustomobject]@{ MailboxCount = 24; FileCount = 100; RuleCount = 0 } }) -Heuristics $script:Heuristics

        ($Score.Breakdown | Where-Object Signal -EQ 'ConsentBurst').Applied | Should -BeTrue
        ($Score.Breakdown | Where-Object Signal -EQ 'MassMailboxAccess').Applied | Should -BeFalse
        ($Score.Breakdown | Where-Object Signal -EQ 'MassFileAccess').Applied | Should -BeTrue
    }

    It 'counts changes, directory actions and new behaviour only in the window and against a real baseline' {
        $Results = New-Results @{
            Changes             = @(
                [pscustomobject]@{ Kind = 'Owner'; InWindow = $true }
                [pscustomobject]@{ Kind = 'Grant'; InWindow = $true; ByApp = $true }
                [pscustomobject]@{ Kind = 'RedirectUri'; InWindow = $false }
            )
            DirectoryActions    = @(
                [pscustomobject]@{ Severity = 'Critical'; Lateral = $true; InWindow = $true }
                [pscustomobject]@{ Severity = 'Critical'; Lateral = $false; InWindow = $false }
            )
            SignInsByCredential = @([pscustomobject]@{ KeyId = 'key-other'; Success = 3 })
            SignInSummary       = [pscustomobject]@{ Success = 3; Resources = @('Microsoft Graph', 'Office 365 Exchange Online') }
        }
        $Applied = @((Get-CIPPNhiScore -Results $Results -Heuristics $script:Heuristics).Breakdown | Where-Object Applied).Signal

        $Applied | Should -Be @('OwnerAdded', 'AccessGrantedByApp', 'NewCredentialInUse', 'NewResourceAccess', 'LateralCredentialAdds')

        $Results.Baseline = [pscustomobject]@{ Total = 3; KeyIds = @(); Resources = @() }
        $Thin = @((Get-CIPPNhiScore -Results $Results -Heuristics $script:Heuristics).Breakdown | Where-Object Applied).Signal
        $Thin | Should -Not -Contain 'NewCredentialInUse' -Because 'a baseline below baseline.minSignIns says nothing about what is new'
    }

    It 'does not count a rotation as a new credential' {
        $Results = New-Results @{
            Exposure            = [pscustomobject]@{ HighestImpact = 'High'; CredentialDetails = @([pscustomobject]@{ KeyId = 'key-rotated'; Purpose = 'Sign-in'; Expired = $false; AddedDateTime = '2026-11-01T00:00:00Z'; Flags = @('AddedRecently', 'Rotation') }) }
            SignInsByCredential = @([pscustomobject]@{ KeyId = 'key-rotated'; Success = 50 })
        }
        $Applied = @((Get-CIPPNhiScore -Results $Results -Heuristics $script:Heuristics).Breakdown | Where-Object Applied).Signal

        $Applied | Should -Not -Contain 'CredentialAdded'
        $Applied | Should -Not -Contain 'NewCredentialInUse'
    }

    It 'counts only the mailboxes and site files the app did not reach before the window' {
        $Mailboxes = @(1..30 | ForEach-Object { [pscustomobject]@{ Mailbox = "user$_@contoso.com"; Count = 5 } })
        $Workload = [pscustomobject]@{ Mailboxes = $Mailboxes; Sites = @([pscustomobject]@{ Site = 'https://contoso.sharepoint.com/sites/hr'; FileCount = 150 }) }
        $Summary = [pscustomobject]@{ MailboxCount = 30; FileCount = 150; RuleCount = 0 }

        # a backup app: the same mailboxes and site every day
        $Backup = Get-CIPPNhiScore -Results (New-Results @{ WorkloadActivity = $Workload; WorkloadSummary = $Summary; WorkloadBaseline = [pscustomobject]@{ Mailboxes = @($Mailboxes.Mailbox); Sites = @('https://contoso.sharepoint.com/sites/hr') } }) -Heuristics $script:Heuristics
        ($Backup.Breakdown | Where-Object Signal -EQ 'MassMailboxAccess').Count | Should -Be 0
        ($Backup.Breakdown | Where-Object Signal -EQ 'MassFileAccess').Applied | Should -BeFalse

        # the same reach from an app that touched none of it before
        $Fresh = Get-CIPPNhiScore -Results (New-Results @{ WorkloadActivity = $Workload; WorkloadSummary = $Summary; WorkloadBaseline = [pscustomobject]@{ Mailboxes = @('user1@contoso.com'); Sites = @() } }) -Heuristics $script:Heuristics
        ($Fresh.Breakdown | Where-Object Signal -EQ 'MassMailboxAccess').Count | Should -Be 29
        ($Fresh.Breakdown | Where-Object Signal -EQ 'MassMailboxAccess').Applied | Should -BeTrue
        ($Fresh.Breakdown | Where-Object Signal -EQ 'MassFileAccess').Applied | Should -BeTrue

        # no baseline: everything counts, and the breakdown says why
        $Unknown = Get-CIPPNhiScore -Results (New-Results @{ WorkloadActivity = $Workload; WorkloadSummary = $Summary }) -Heuristics $script:Heuristics
        ($Unknown.Breakdown | Where-Object Signal -EQ 'MassMailboxAccess').Applied | Should -BeTrue
        ($Unknown.Breakdown | Where-Object Signal -EQ 'MassMailboxAccess').Description | Should -BeLike '*could not be read*'
    }

    It 'flags sign-in and workload volume at the spike factor of the daily baseline rate, and never on a capped count' {
        # baseline: 23 sign-ins a day for 23 days; window: 7 days
        $Base = @{ AnalysisWindowDays = 7; BaselineDays = 23; Baseline = [pscustomobject]@{ Total = 529; KeyIds = @(); Resources = @(); AttachedResources = @() } }
        $Spike = Get-CIPPNhiScore -Results (New-Results ($Base + @{ SignInSummary = [pscustomobject]@{ Total = 1000; Success = 1000 } })) -Heuristics $script:Heuristics
        ($Spike.Breakdown | Where-Object Signal -EQ 'SignInVolumeSpike').Count | Should -Be 6
        ($Spike.Breakdown | Where-Object Signal -EQ 'SignInVolumeSpike').Applied | Should -BeTrue

        $Normal = Get-CIPPNhiScore -Results (New-Results ($Base + @{ SignInSummary = [pscustomobject]@{ Total = 200; Success = 200 } })) -Heuristics $script:Heuristics
        ($Normal.Breakdown | Where-Object Signal -EQ 'SignInVolumeSpike').Applied | Should -BeFalse

        $Capped = Get-CIPPNhiScore -Results (New-Results ($Base + @{ SignInSummary = [pscustomobject]@{ Total = 100000; Success = 100000; Capped = $true } })) -Heuristics $script:Heuristics
        ($Capped.Breakdown | Where-Object Signal -EQ 'SignInVolumeSpike').Count | Should -Be 0

        # 230 operations before the window (10 a day), 700 in the window (100 a day)
        $Workload = $Base + @{ WorkloadActivity = [pscustomobject]@{ ByOperation = @([pscustomobject]@{ Operation = 'MailItemsAccessed'; Count = 700 }) } }
        $Busy = Get-CIPPNhiScore -Results (New-Results ($Workload + @{ WorkloadBaseline = [pscustomobject]@{ Mailboxes = @(); Sites = @(); Operations = 230; Complete = $true } })) -Heuristics $script:Heuristics
        ($Busy.Breakdown | Where-Object Signal -EQ 'WorkloadVolumeSpike').Count | Should -Be 10
        ($Busy.Breakdown | Where-Object Signal -EQ 'WorkloadVolumeSpike').Applied | Should -BeTrue
        $Partial = Get-CIPPNhiScore -Results (New-Results ($Workload + @{ WorkloadBaseline = [pscustomobject]@{ Mailboxes = @(); Sites = @(); Operations = 230; Complete = $false } })) -Heuristics $script:Heuristics
        ($Partial.Breakdown | Where-Object Signal -EQ 'WorkloadVolumeSpike').Applied | Should -BeFalse -Because 'a capped baseline is a floor, not a rate'
    }

    It 'flags mail sending and anonymous links only when the app did neither before the window' {
        $Summary = [pscustomobject]@{ MailboxCount = 1; FileCount = 0; RuleCount = 0; SendCount = 40; AnonymousLinkCount = 3 }
        $Quiet = [pscustomobject]@{ Mailboxes = @(); Sites = @(); Operations = 0; SendCount = 0; AnonymousLinkCount = 0; Complete = $true }
        $Applied = @((Get-CIPPNhiScore -Results (New-Results @{ WorkloadSummary = $Summary; WorkloadBaseline = $Quiet }) -Heuristics $script:Heuristics).Breakdown | Where-Object Applied).Signal
        $Applied | Should -Contain 'NewMailSending'
        $Applied | Should -Contain 'NewAnonymousLinks'

        # a notification app that always sends, and a portal that always shares
        $Usual = [pscustomobject]@{ Mailboxes = @(); Sites = @(); Operations = 500; SendCount = 300; AnonymousLinkCount = 20; Complete = $true }
        $Applied = @((Get-CIPPNhiScore -Results (New-Results @{ WorkloadSummary = $Summary; WorkloadBaseline = $Usual }) -Heuristics $script:Heuristics).Breakdown | Where-Object Applied).Signal
        $Applied | Should -Not -Contain 'NewMailSending'
        $Applied | Should -Not -Contain 'NewAnonymousLinks'

        $NoBaseline = Get-CIPPNhiScore -Results (New-Results @{ WorkloadSummary = $Summary }) -Heuristics $script:Heuristics
        ($NoBaseline.Breakdown | Where-Object Signal -EQ 'NewMailSending').Description | Should -BeLike '*could not be read*'
    }

    It 'rates elevation by who received it, and not for a provisioning tool or CIPP' {
        $Grant = { param($Recipient, $Impact = 'Critical', $InWindow = $true) [pscustomobject]@{ Kind = 'Elevation'; Recipient = $Recipient; Impact = $Impact; InWindow = $InWindow; Severity = 'Critical' } }
        $Window = @((& $Grant 'Self'), (& $Grant 'App'), (& $Grant 'User'), (& $Grant 'App' 'Low'))
        $Persisted = [pscustomobject]@{ Kind = 'AppPersistence'; CreatedApp = $true; InWindow = $true; Severity = 'Critical' }

        $Score = Get-CIPPNhiScore -Results (New-Results @{ DirectoryActions = $Window + $Persisted }) -Heuristics $script:Heuristics
        $Applied = @($Score.Breakdown | Where-Object Applied).Signal
        foreach ($Signal in 'SelfElevation', 'AppElevation', 'UserElevation', 'ElevationChain') { $Applied | Should -Contain $Signal }
        ($Score.Breakdown | Where-Object Signal -EQ 'AppElevation').Count | Should -Be 1 -Because 'a low-impact grant is listed, not scored'
        $Applied | Should -Not -Contain 'CriticalDirectoryActions' -Because 'elevation is not counted again as a directory change'

        # it granted high-impact access to others before the window too: a provisioning tool
        $Tool = Get-CIPPNhiScore -Results (New-Results @{ DirectoryActions = $Window + @((& $Grant 'App' 'High' $false)) }) -Heuristics $script:Heuristics
        $Applied = @($Tool.Breakdown | Where-Object Applied).Signal
        $Applied | Should -Contain 'SelfElevation'
        $Applied | Should -Not -Contain 'AppElevation'
        ($Tool.Breakdown | Where-Object Signal -EQ 'AppElevation').Description | Should -BeLike '*provisions access*'

        $Cipp = Get-CIPPNhiScore -Results (New-Results @{ DirectoryActions = $Window; Subject = [pscustomobject]@{ IsCippApp = $true } }) -Heuristics $script:Heuristics
        @($Cipp.Breakdown | Where-Object { $_.Applied -and $_.Signal -like '*Elevation*' }).Count | Should -Be 0
        ($Cipp.Breakdown | Where-Object Signal -EQ 'SelfElevation').Description | Should -BeLike "*CIPP's own app*"
    }

    It 'rates a dormant app that woke up, and Identity Protection''s verdict' {
        $Results = New-Results @{ Dormant = $true; RiskState = [pscustomobject]@{ riskState = 'confirmedCompromised'; riskLevel = 'high' } }
        $Applied = @((Get-CIPPNhiScore -Results $Results -Heuristics $script:Heuristics).Breakdown | Where-Object Applied).Signal

        $Applied | Should -Be @('ConfirmedCompromised', 'DormantAwakened')
    }
}
