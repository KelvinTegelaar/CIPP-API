BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    # The shipped heuristics and malicious-app catalog are read through $env:CIPPRootPath.
    $env:CIPPRootPath = $RepoRoot

    # Platform helpers the run calls; each is a stub so Mock has something to replace.
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor, $Select, $useSystemMailbox, $NoAuthCheck, [switch]$Compliance, $ApiVersion, [switch]$AsApp) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination, $scope, $ComplexFilter, $NoAuthCheck, [switch]$verbose) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $NoAuthCheck, $scope, $NoPaginateIds, $Version, $Headers) }
    function Get-CIPPTenantCapabilities { param($TenantFilter, $APIName, $Headers) }
    function Get-CIPPGeoIPLocationBatch { param([string[]]$IPs) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    function Get-NormalizedError { param($message) $message }
    function Set-CippBecCaseContext { param($CaseId) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    # Live progress (the async-deployment rows the page polls)
    function Get-CIPPAsyncDeployment { param($JobId) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TenantFilter) $JobId }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Search-CIPPBecAuditLog { param($TenantFilter, $StartDate, $EndDate, $Operations, $UserIds, $RecordType, $ObjectIds, $Anchor, $PageSize, $MaxPages) }
    function Get-CIPPBecMessageTrace { param($TenantFilter, $SenderAddress, $RecipientAddress, $StartDate, $EndDate, $Anchor, $PageSize, $MaxPages) }
    # Full-scope collectors
    function Get-CIPPBecMailboxInventory { param($TenantFilter, $UserPrincipalName, $Heuristics, $AcceptedDomains) }
    function Get-CIPPBecUserGrants { param($TenantFilter, $UserId, $Heuristics, $RogueAppFeed) }
    function Get-CIPPBecTransportRules { param($TenantFilter, $StartDate, $EndDate, $Heuristics, $Anchor) }
    function Get-CIPPBecReceivedMailFindings { param($TenantFilter, $UserPrincipalName, $StartDate, $EndDate, $Heuristics, $AcceptedDomains, $Anchor, [switch]$IncludeDefender) }
    function Get-CIPPBecDirectoryAudits { param($TenantFilter, $UserId, $StartDate, $Heuristics, $Cap) }
    function Get-CIPPBecRegisteredDevices { param($TenantFilter, $UserId, $StartDate) }
    function Get-CIPPBecNonInteractiveSignIns { param($TenantFilter, $UserId, $UsageLocation, $StartDate) }
    function Get-CIPPBecMailActivity { param($TenantFilter, $UserPrincipalName, $StartDate, $EndDate, $Heuristics, $Anchor) }
    function Get-CIPPBecRiskState { param($TenantFilter, $UserId, $StartDate, $Cap) }
    function Get-CIPPBecRogueAppFeed { }
    function Get-CIPPPartnerUserLookup { @{} }
    # The IP analysis has its own suite; here it only has to be wired in and its verdicts stamped.
    function Get-CIPPBecAttackerActivity { param($TenantFilter, $UserPrincipalName, $StartDate, $EndDate, $Heuristics, $Verdicts, $SignIns, $NonInteractiveSignIns, $MailRecords, $SharingChanges, $KnownSubjects, $Anchor) }
    function Get-CIPPBecDelegatedAccess { param($TenantFilter, $UserPrincipalName, $UserDisplayName, $PermissionChanges, $MailActivity, $AttackerMail) }
    function Get-CIPPBecBlastRadius { param($TenantFilter, $UserId, $UserPrincipalName, $Verdicts, $Peers, $StartDate, $EndDate, $Heuristics, $Anchor) }
    function Invoke-CIPPBecIPAnalysis { param($TenantFilter, $UserId, $UserPrincipalName, $Results, $Heuristics, $WindowStart, $UsageLocation, $Anchor, $Baseline, $KnownPeers, $Overrides, $ExtraPeers, $TechnicianIPs, [switch]$SampleColleagues) }

    # Real pieces under test alongside the run
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AuditLogs/Resolve-CIPPAuditActor.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCaseId.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecScore.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRunSteps.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecErrorInfo.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Set-CIPPBecIPVerdictStamp.ps1')
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-BECRun.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function Empty { New-CIPPBecCollectorResult -Data @() }
    $script:Item = @{ TenantFilter = 'contoso.com'; UserID = 'user-guid'; userName = 'victim@contoso.com'; CaseId = 'BEC-20260820120000-test01' }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Push-BECRun' {
    BeforeEach {
        $script:Saved = $null
        # the last write wins: the run writes Running first, then Completed or Error
        Mock Set-CIPPBecReport { $script:Saved = @{ TenantFilter = $TenantFilter; CaseId = $CaseId; Properties = $Properties; Results = $Results } }
        $script:StepCalls = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPAsyncDeploymentStep { $script:StepCalls.Add(@{ JobId = $JobId; Name = $Name; Index = $StepIndex; Status = $StepStatus; Message = $Message }) }
        $script:StatusCalls = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPAsyncDeploymentStatus { $script:StatusCalls.Add(@{ JobId = $JobId; Name = $Name; Status = $Status; Logs = $Logs }) }
        Mock Get-CIPPAsyncDeployment { @() }
        Mock New-CIPPAsyncDeployment { $JobId }
        Mock Write-LogMessage { }
        Mock Set-CippBecCaseContext { }
        Mock Get-CIPPGeoIPLocationBatch { @{ '203.0.113.10' = [pscustomobject]@{ CountryOrRegion = 'NG'; City = 'Lagos' } } }
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-AdminAuditLogConfig' { [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true } }
                'Get-InboxRule' { [pscustomobject]@{ Name = 'Hide invoices'; Identity = 'r1'; Enabled = $true; MoveToFolder = 'RSS Feeds'; MarkAsRead = $true; Description = 'x' }, [pscustomobject]@{ Name = 'Junk E-Mail Rule'; Identity = 'junk' } }
                'Get-MailboxJunkEmailConfiguration' { [pscustomobject]@{ TrustedSendersAndDomains = @('partner@example.org'); BlockedSendersAndDomains = @() } }
                'Get-AcceptedDomain' { [pscustomobject]@{ DomainName = 'contoso.com' }, [pscustomobject]@{ DomainName = 'contoso.onmicrosoft.com' } }
                default { @() }
            }
        }
        Mock Search-CIPPBecAuditLog {
            if ($Operations -contains 'New-InboxRule') {
                [pscustomobject]@{ Complete = $true; Cap = $null; Pages = 1; Records = @([pscustomobject]@{ Identity = 'a1'; Operation = 'New-InboxRule'; AuditData = [pscustomobject]@{ Operation = 'New-InboxRule'; UserId = 'victim@contoso.com'; CreationTime = '2026-08-19T01:00:00Z'; ClientIP = '203.0.113.10:51234'; ObjectId = 'victim@contoso.com\Hide invoices'; Parameters = @([pscustomobject]@{ Name = 'Name'; Value = 'Hide invoices' }, [pscustomobject]@{ Name = 'MoveToFolder'; Value = 'RSS Feeds' }) } }) }
            } elseif ($Operations -contains 'Add-MailboxPermission') {
                # one grant on the investigated mailbox (the delegation join below picks it up), page cap hit
                [pscustomobject]@{ Complete = $false; Cap = '10 pages of 5000 records'; Pages = 10; Records = @([pscustomobject]@{ Identity = 'p1'; Operation = 'Add-MailboxPermission'; AuditData = [pscustomobject]@{ Operation = 'Add-MailboxPermission'; UserKey = 'admin@contoso.com'; CreationTime = '2026-08-19T05:00:00Z'; ClientIP = '203.0.113.10'; ObjectId = 'contoso.onmicrosoft.com/Users/Victim'; Parameters = @([pscustomobject]@{ Name = 'Identity'; Value = 'victim@contoso.com' }, [pscustomobject]@{ Name = 'User'; Value = 'helper@contoso.com' }, [pscustomobject]@{ Name = 'AccessRights'; Value = 'FullAccess' }) } }) }
            } else {
                [pscustomobject]@{ Complete = $true; Cap = $null; Pages = 1; Records = @() }
            }
        }
        Mock Get-CIPPBecMessageTrace { [pscustomobject]@{ Complete = $true; Cap = $null; Pages = 1; Rows = @([pscustomobject]@{ MessageTraceId = 't1'; Status = 'Delivered'; Subject = 'Hi'; RecipientAddress = 'a@example.org'; Received = '2026-08-19T02:00:00Z'; FromIP = '203.0.113.10' }) } }
        # Eligible tenant: Entra ID P2, Defender for Office 365 Plan 2 and Intune present, so the
        # licence preflight lets Identity Protection, Defender and the device query run.
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM_P2 = $true; THREAT_INTELLIGENCE = $true; INTUNE_A = $true } }
        Mock New-GraphGetRequest {
            if ($uri -like '*signIns*') {
                [pscustomobject]@{ id = 's1'; createdDateTime = '2026-08-19T03:00:00Z'; resourceDisplayName = 'Office 365 Exchange Online'; clientAppUsed = 'Browser'; conditionalAccessStatus = 'success'; status = [pscustomobject]@{ errorCode = 0 }; ipAddress = '203.0.113.10'; location = [pscustomobject]@{ countryOrRegion = 'NG'; city = 'Lagos' } }
            } else { @() }
        }
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                switch -Wildcard ($Request.id) {
                    'Users' { [pscustomobject]@{ id = 'Users'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = 'user-guid'; displayName = 'Victim'; userPrincipalName = 'victim@contoso.com'; createdDateTime = '2025-01-01T00:00:00Z'; lastPasswordChangeDateTime = '2025-01-01T00:00:00Z' }, [pscustomobject]@{ id = '1b4e28ba-2fa1-11d2-883f-0016d3cca427'; displayName = 'Assistant'; userPrincipalName = 'assistant@contoso.com'; createdDateTime = '2025-01-01T00:00:00Z'; lastPasswordChangeDateTime = '2025-01-01T00:00:00Z' }) } } }
                    # createdDateTime is relative to now: the score's RecentMfaMethods signal only counts a method registered inside the (live-anchored) analysis window, so a fixed date would age out and silently drop 2 points from the expected score.
                    'MFADevices' { [pscustomobject]@{ id = 'MFADevices'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'; id = 'm1'; displayName = 'Pixel'; createdDateTime = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') }) } } }
                    'NewSPs' { [pscustomobject]@{ id = 'NewSPs'; status = 200; body = [pscustomobject]@{ value = @() } } }
                    'IntuneDevices' { [pscustomobject]@{ id = 'IntuneDevices'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'No Intune licence' } } } }
                    'SuspectUser' { [pscustomobject]@{ id = 'SuspectUser'; status = 200; body = [pscustomobject]@{ id = 'user-guid'; displayName = 'Victim'; userPrincipalName = 'victim@contoso.com'; usageLocation = 'NL'; country = 'Netherlands' } } }
                    'MaliciousSPs*' { [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @() } } }
                }
            }
        }
        Mock Get-CIPPBecMailboxInventory { [pscustomobject]@{ MailboxState = (New-CIPPBecCollectorResult -Data ([pscustomobject]@{ HasForwarding = $true; ForwardingSmtpAddress = 'smtp:x@example.org' }) -Count 1); Delegations = (New-CIPPBecCollectorResult -Data @([pscustomobject]@{ PermissionType = 'FullAccess'; Trustee = 'outsider@example.org'; Flagged = $true }, [pscustomobject]@{ PermissionType = 'FullAccess'; Trustee = 'Helper@contoso.com'; Flagged = $false }, [pscustomobject]@{ PermissionType = 'SendOnBehalf'; Trustee = '1b4e28ba-2fa1-11d2-883f-0016d3cca427'; Flagged = $false })); AddIns = (Empty) } }
        Mock Get-CIPPBecUserGrants { New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Id = 'g1'; Risk = 'CatalogMatch'; Flagged = $true }) }
        Mock Get-CIPPBecTransportRules { [pscustomobject]@{ Changes = (New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Operation = 'New-TransportRule'; RuleName = 'Exfil'; ClientIP = '203.0.113.10'; Flagged = $true })); Flagged = (Empty) } }
        Mock Get-CIPPBecReceivedMailFindings { [pscustomobject]@{ Findings = (Empty); Defender = (New-CIPPBecCollectorResult -Data @() -Error 'Invalid subscription') } }
        Mock Get-CIPPBecDirectoryAudits { Empty }
        Mock Get-CIPPBecRegisteredDevices { Empty }
        Mock Get-CIPPBecNonInteractiveSignIns { Empty }
        Mock Invoke-CIPPBecIPAnalysis {
            $script:IPAnalysisInput = $Results
            $script:IPAnalysisTechnicians = $TechnicianIPs
            [pscustomobject]@{
                Baseline    = New-CIPPBecCollectorResult -Data ([pscustomobject]@{ Successful = 12 }) -Count 12
                Guidance    = New-CIPPBecCollectorResult -Data @()
                PeersResult = New-CIPPBecCollectorResult -Data @()
                Peers       = @{}
                Geo         = @{}
                Verdicts    = @([pscustomobject]@{ IP = '203.0.113.10'; Verdict = 'LikelyAttacker'; SuccessfulSignIns = 1; Activities = 2 })
                Events      = @()
            }
        }
        Mock Get-CIPPBecAttackerActivity {
            $script:AttackerInput = @{ Verdicts = $Verdicts; MailRecords = $MailRecords; KnownSubjects = $KnownSubjects }
            $Mail = New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Operation = 'MailItemsAccessed'; Subject = 'Wire details'; IPVerdict = 'LikelyAttacker'; MailboxOwner = 'victim@contoso.com' })
            $Mail | Add-Member -NotePropertyName Summary -NotePropertyValue ([pscustomobject]@{ MessagesOpened = 1 }) -Force
            $Forms = New-CIPPBecCollectorResult -Data @()
            $Forms | Add-Member -NotePropertyName Summary -NotePropertyValue ([pscustomobject]@{ FlaggedActions = 0; Forms = @() }) -Force
            [pscustomobject]@{ Mail = $Mail; Files = (Empty); LinkUsage = (Empty); Forms = $Forms; Subjects = $null }
        }
        Mock Get-CIPPBecDelegatedAccess { New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Mailbox = 'ceo@contoso.com'; Flagged = $false }) }
        Mock Get-CIPPBecBlastRadius { $script:BlastPeers = $Peers; New-CIPPBecCollectorResult -Data @([pscustomobject]@{ UserPrincipalName = 'cfo@contoso.com'; Reached = $false }) }
        Mock Get-CIPPBecMailActivity { $R = Empty; $R | Add-Member -NotePropertyName Summary -NotePropertyValue ([pscustomobject]@{ HardDeleteExceeded = $false }) -Force; $R }
        Mock Get-CIPPBecRiskState { New-CIPPBecCollectorResult -Data ([pscustomobject]@{ Listed = $false; Detections = @() }) -Count 0 }
        Mock Get-CIPPBecRogueAppFeed { [pscustomobject]@{ Apps = @{}; HuntressAvailable = $false } }
        Mock Get-CIPPPartnerUserLookup { @{ '0123abcd-4567-4890-8abc-def012345678' = @{ userPrincipalName = 'tech@msp.example' } } }
    }

    It 'runs every collector (a legacy Scope on the queue item is ignored), flattens their data and scores the signals' {
        Push-BECRun -Item ($script:Item + @{ Scope = 'Quick'; RequestedFromIP = '192.0.2.77'; RequestedBy = 'tech@msp.com' })
        foreach ($Collector in 'Get-CIPPBecMailboxInventory', 'Get-CIPPBecUserGrants', 'Get-CIPPBecTransportRules', 'Get-CIPPBecReceivedMailFindings', 'Get-CIPPBecDirectoryAudits', 'Get-CIPPBecRegisteredDevices', 'Get-CIPPBecNonInteractiveSignIns', 'Get-CIPPBecMailActivity', 'Get-CIPPBecRiskState') {
            Should -Invoke $Collector -Times 1 -Because "$Collector runs on Full scope"
        }
        Should -Invoke Get-CIPPBecMailboxInventory -Times 1 -ParameterFilter { $AcceptedDomains -contains 'contoso.com' -and $UserPrincipalName -eq 'victim@contoso.com' }
        Should -Invoke Get-CIPPBecReceivedMailFindings -Times 1 -ParameterFilter { $IncludeDefender.IsPresent }
        Should -Invoke Get-CIPPBecNonInteractiveSignIns -Times 1 -ParameterFilter { $UsageLocation -eq 'NL' }
        $R = $script:Saved.Results
        $R.MailboxState.HasForwarding | Should -BeTrue
        $R.Delegations.Count | Should -Be 3
        $Helper = $R.Delegations | Where-Object { $_.Trustee -eq 'Helper@contoso.com' }
        $Helper.GrantedInWindow | Should -BeTrue -Because 'the Add-MailboxPermission for this mailbox is in the window'
        $Helper.Flagged | Should -BeTrue -Because 'a grant made in the window is flagged even for an internal trustee'
        ($R.Delegations | Where-Object { $_.Trustee -eq 'outsider@example.org' }).GrantedInWindow | Should -BeFalse
        $Assistant = $R.Delegations | Where-Object { $_.PermissionType -eq 'SendOnBehalf' }
        $Assistant.Trustee | Should -Be 'assistant@contoso.com' -Because 'directory ids resolve to the UPN'
        $Assistant.TrusteeId | Should -Be '1b4e28ba-2fa1-11d2-883f-0016d3cca427'
        $R.Delegations[0].Flagged | Should -BeTrue -Because 'flagged delegations sort first'
        $R.UserGrants[0].Risk | Should -Be 'CatalogMatch'
        $R.TransportRuleChanges[0].Country | Should -Be 'NG' -Because 'full-scope client IPs go through the same geo lookup'
        $R.TransportRuleChanges[0].ForeignLocation | Should -BeTrue
        $R.InboxRuleChanges[0].ClientIP | Should -Be '203.0.113.10' -Because 'the client port is dropped so one host correlates as one'
        $R.InboxRuleChanges[0].Country | Should -Be 'NG'
        $R.InboxRuleChanges[0].AuditData.Operation | Should -Be 'New-InboxRule' -Because 'the raw audit record rides along for the More Info panel'
        $R.InboxRuleChanges[0].ActorKind | Should -Be 'User' -Because 'the mailbox owner made the rule'
        $R.LocationAnalysis.ForeignTransportRuleChangeCount | Should -Be 1
        $R.Completeness.DefenderDetections.Complete | Should -BeFalse
        $R.Completeness.DefenderDetections.Error | Should -Be 'Invalid subscription'
        $R.Completeness.Delegations.Complete | Should -BeTrue
        $R.Completeness.RiskState.Complete | Should -BeTrue
        # the IP analysis gets the rows it judges, and its verdicts land on the case and on the rows
        $script:IPAnalysisInput.InboxRuleChanges[0].ClientIP | Should -Be '203.0.113.10'
        $script:IPAnalysisInput.SuspectUserSignIns[0].IPAddress | Should -Be '203.0.113.10'
        $R.IPVerdicts[0].Verdict | Should -Be 'LikelyAttacker'
        $R.IPBaseline.Successful | Should -Be 12
        $script:IPAnalysisTechnicians[0].IP | Should -Be '192.0.2.77' -Because 'the technician who started the run gets a trusted start'
        $R.IPTechnicians[0].By | Should -Be 'tech@msp.com'
        $R.InboxRuleChanges[0].IPVerdict | Should -Be 'LikelyAttacker'
        $R.SuspectUserSignIns[0].IPVerdict | Should -Be 'LikelyAttacker'
        $R.Completeness.SignInBaseline.Complete | Should -BeTrue
        $R.Completeness.IPVerdicts.Count | Should -Be 1
        # the attacker-activity pass gets the verdicts, the raw mailbox records and the known subjects
        $script:AttackerInput.Verdicts[0].IP | Should -Be '203.0.113.10'
        $script:AttackerInput.KnownSubjects.Count | Should -BeGreaterOrEqual 0
        $R.AttackerMailActivity[0].Subject | Should -Be 'Wire details'
        $R.AttackerMailSummary.MessagesOpened | Should -Be 1
        $R.DelegatedAccess[0].Mailbox | Should -Be 'ceo@contoso.com'
        $R.UserPrincipalName | Should -Be 'victim@contoso.com'
        $R.Completeness.AttackerMailActivity.Complete | Should -BeTrue
        $R.Completeness.DelegatedAccess.Complete | Should -BeTrue
        $R.BlastRadius[0].UserPrincipalName | Should -Be 'cfo@contoso.com'
        $R.Completeness.BlastRadius.Complete | Should -BeTrue
        $script:BlastPeers | Should -BeOfType [hashtable] -Because "the analysis' tenant-wide sign-in lookup is reused"
        # Quick score 21 + flagged delegation 2 + catalog grant 5 + risky transport change 4 + attacker IP 4 + attacker mail 3
        $R.Score.Value | Should -Be 39
    }

    It 'resolves a missing UPN from the object id, writes it back, and runs the investigation' {
        # A run queued with only the object id (an API/MCP caller, or a page race) must not run the
        # mailbox collectors with an empty UPN; the run resolves it from the id first.
        Mock New-GraphGetRequest { [pscustomobject]@{ userPrincipalName = 'victim@contoso.com'; displayName = 'Victim' } } -ParameterFilter { $uri -like '*/users/user-guid*' }
        Push-BECRun -Item @{ TenantFilter = 'contoso.com'; UserID = 'user-guid'; userName = ''; CaseId = 'BEC-20260820120000-test02' }
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like '*/users/user-guid*' }
        Should -Invoke Set-CIPPBecReport -Times 1 -ParameterFilter { $Properties.UserPrincipalName -eq 'victim@contoso.com' }
        Should -Invoke Get-CIPPBecMailboxInventory -Times 1 -ParameterFilter { $UserPrincipalName -eq 'victim@contoso.com' }
        $script:Saved.Properties.Status | Should -Be 'Completed'
    }

    It 'fails a blank-UPN run cleanly when the object id cannot be resolved, without running the collectors' {
        # the default New-GraphGetRequest mock returns nothing for an unknown users/{id} lookup
        Push-BECRun -Item @{ TenantFilter = 'contoso.com'; UserID = 'ghost-guid'; userName = ''; CaseId = 'BEC-20260820120000-test03' }
        $script:Saved.Properties.Status | Should -Be 'Error'
        $script:Saved.Properties.ErrorMessage | Should -Match 'user principal name'
        Should -Invoke Get-CIPPBecMailboxInventory -Times 0
        Should -Invoke Search-CIPPBecAuditLog -Times 0
    }

    It 'degrades a collector that throws to an error marker without failing the run' {
        Mock Get-CIPPBecUserGrants { throw 'Graph exploded' }
        Push-BECRun -Item ($script:Item + @{ Scope = 'Full' })
        $R = $script:Saved.Results
        $script:Saved.Properties.Status | Should -Be 'Completed'
        $R.Completeness.UserGrants.Complete | Should -BeFalse
        $R.Completeness.UserGrants.Error | Should -Match 'Graph exploded'
        $R.UserGrants.Count | Should -Be 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $message -like '*collector UserGrants failed*' }
    }

    It 'marks the audit-dependent checks incomplete when the unified audit log is disabled' {
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-AdminAuditLogConfig' { [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $false } }
                'Get-InboxRule' { @() }
                'Get-MailboxJunkEmailConfiguration' { [pscustomobject]@{ TrustedSendersAndDomains = @(); BlockedSendersAndDomains = @() } }
                default { @() }
            }
        }
        Push-BECRun -Item $script:Item
        $R = $script:Saved.Results
        $R.ExtractResult | Should -Match 'disabled'
        $R.Completeness.AuditLog.Complete | Should -BeFalse
        $R.Completeness.AuditLog.Error | Should -Match 'disabled'
        $R.InboxRuleChanges.Count | Should -Be 0
        Should -Invoke Search-CIPPBecAuditLog -Times 0
    }

    It 'records a failed run instead of leaving it waiting' {
        Mock New-GraphBulkRequest { throw 'bulk blew up' }
        Push-BECRun -Item $script:Item
        $script:Saved.Properties.Status | Should -Be 'Error'
        $script:Saved.Properties.ErrorMessage | Should -Match 'bulk blew up'
        $script:Saved.Results | Should -BeNullOrEmpty
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($CaseId) }
    }

    Context 'live progress (the async-deployment job the page polls)' {
        It 'creates the job when the queue did not, marks the run Running, walks each of the fourteen phases running then done, and ends succeeded' {
            Push-BECRun -Item $script:Item
            Should -Invoke New-CIPPAsyncDeployment -Times 1 -ParameterFilter { $JobId -eq 'BEC-20260820120000-test01' -and $Names -contains 'victim@contoso.com' -and @($StepTitles).Count -eq 14 -and $Source -eq 'BEC' }
            Should -Invoke Set-CIPPBecReport -Times 1 -ParameterFilter { $Properties.Status -eq 'Running' -and $Properties.StartedAt }
            @($script:StatusCalls.Status) | Should -Be @('running', 'succeeded')
            $script:StatusCalls[-1].Logs | Should -Match 'threat level High'
            @(($script:StepCalls | Where-Object { $_.Status -eq 'running' }).Index) | Should -Be @(0..13) -Because 'the phases run in order'
            @(($script:StepCalls | Where-Object { $_.Status -eq 'succeeded' }).Index) | Should -Be @(0..13)
            ($script:StepCalls | Where-Object { $_.Status -eq 'succeeded' })[-1].Message | Should -Match '^Threat level High'
            @($script:StepCalls | Where-Object { $_.Status -eq 'failed' }).Count | Should -Be 0
            $script:StepCalls | ForEach-Object { $_.JobId | Should -Be 'BEC-20260820120000-test01'; $_.Name | Should -Be 'victim@contoso.com' }
        }

        It 'marks the phase that was running as failed, and the job failed, when the run throws' {
            Mock New-GraphBulkRequest { throw 'bulk blew up' }
            Push-BECRun -Item $script:Item
            @($script:StatusCalls.Status) | Should -Be @('running', 'failed')
            $Failed = @($script:StepCalls | Where-Object { $_.Status -eq 'failed' })
            $Failed.Count | Should -Be 1
            $Failed[0].Index | Should -Be 4 -Because 'the bulk Graph read belongs to the tenant phase'
            $Failed[0].Message | Should -Match 'bulk blew up'
        }

        It 'recreates the job at start so a Craft retry shows a clean progression instead of the dead attempt''s steps' {
            Mock Get-CIPPAsyncDeployment { @([pscustomobject]@{ Name = 'victim@contoso.com'; Status = 'running'; Steps = @([pscustomobject]@{ Title = 'x'; Status = 'succeeded'; Message = 'Done' }); Logs = '' }) }
            Push-BECRun -Item $script:Item
            Should -Invoke New-CIPPAsyncDeployment -Times 1 -ParameterFilter { $JobId -eq 'BEC-20260820120000-test01' -and @($StepTitles).Count -eq 14 }
            @($script:StatusCalls.Status) | Should -Be @('running', 'succeeded')
        }
    }

    It 'mints a case id when the queue item carries none' {
        Push-BECRun -Item @{ TenantFilter = 'contoso.com'; UserID = 'user-guid'; userName = 'victim@contoso.com' }
        $script:Saved.CaseId | Should -Match '^BEC-\d{14}-[0-9a-f]{6}$'
    }

    It 'stamps partner (GDAP) and CIPP actors on audited rows so the case can list them separately' {
        Mock Search-CIPPBecAuditLog {
            if ($Operations -contains 'New-InboxRule') {
                [pscustomobject]@{ Complete = $true; Cap = $null; Pages = 1; Records = @([pscustomobject]@{ Identity = 'a2'; Operation = 'New-InboxRule'; AuditData = [pscustomobject]@{ Operation = 'New-InboxRule'; UserId = 'user_0123abcd456748908abcdef012345678@contoso.onmicrosoft.com'; CreationTime = '2026-08-19T02:00:00Z'; ClientIP = '198.51.100.7'; ObjectId = 'victim@contoso.com\Partner rule'; Parameters = @([pscustomobject]@{ Name = 'Name'; Value = 'Partner rule' }) } }) }
            } else { [pscustomobject]@{ Complete = $true; Cap = $null; Pages = 1; Records = @() } }
        }
        Mock Get-CIPPBecDirectoryAudits { New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Id = 'd1'; ActivityDateTime = '2026-08-19T03:00:00Z'; Activity = 'Reset user password'; InitiatedBy = 'CIPP-SAM'; InitiatedByType = 'Application'; InitiatedById = '11111111-2222-4333-8444-555555555555'; Flagged = $true }) }
        $PriorAppId = $env:ApplicationID
        $env:ApplicationID = '11111111-2222-4333-8444-555555555555'
        try {
            Push-BECRun -Item $script:Item
        } finally {
            $env:ApplicationID = $PriorAppId
        }
        $R = $script:Saved.Results
        $R.InboxRuleChanges[0].ActorKind | Should -Be 'Partner'
        $R.InboxRuleChanges[0].ActorResolved | Should -Be 'tech@msp.example'
        $R.DirectoryAudits[0].ActorKind | Should -Be 'CIPP'
        $R.DirectoryAudits[0].ActorResolved | Should -Be 'CIPP (service principal)'
    }

    It 'does nothing without a tenant or user' {
        Push-BECRun -Item @{ TenantFilter = 'contoso.com' }
        Should -Invoke Set-CIPPBecReport -Times 0
    }

    It 'preflight skips Identity Protection when the tenant has no Entra ID P2 - without calling it' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM = $true; INTUNE_A = $true } }
        Push-BECRun -Item ($script:Item + @{ Scope = 'Full' })
        Should -Invoke Get-CIPPBecRiskState -Times 0 -Because 'the licence preflight skips it instead of running it to fail'
        $R = $script:Saved.Results
        $R.Completeness.RiskState.Skipped | Should -BeTrue
        $R.Completeness.RiskState.Requirement | Should -Match 'Entra ID P2'
        $script:Saved.Properties.Status | Should -Be 'Completed'
    }

    It 'preflight skips the Intune device check when the tenant has no Intune plan - without querying it' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ AAD_PREMIUM_P2 = $true } }
        Push-BECRun -Item $script:Item
        Should -Invoke New-GraphBulkRequest -Times 0 -ParameterFilter { @($Requests | Where-Object { $_.id -eq 'IntuneDevices' }).Count -gt 0 } -Because 'the licence preflight drops the request instead of sending it to fail'
        $R = $script:Saved.Results
        $R.Completeness.IntuneDevices.Skipped | Should -BeTrue
        $R.Completeness.IntuneDevices.Requirement | Should -Match 'Intune licence'
        $R.Completeness.IntuneDevices.Error | Should -BeNullOrEmpty
        $R.IntuneDevices | Should -BeNullOrEmpty
        $script:Saved.Properties.Status | Should -Be 'Completed'
    }

    It 'runs every gated check when the plan read itself fails - never skips on a failed preflight' {
        Mock Get-CIPPTenantCapabilities { throw 'CacheCapabilities unavailable' }
        Push-BECRun -Item $script:Item
        Should -Invoke Get-CIPPBecRiskState -Times 1
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter { @($Requests | Where-Object { $_.id -eq 'IntuneDevices' }).Count -gt 0 }
        $script:Saved.Results.Completeness.RiskState.Skipped | Should -BeFalse
        $script:Saved.Properties.Status | Should -Be 'Completed'
    }

    It 'classifies a user without a mailbox as skipped mailbox checks, not failed ones' {
        Mock Get-CIPPBecMailboxInventory { $E = New-CIPPBecCollectorResult -Data @() -Error 'Get-Mailbox: Ex41BAF5|Microsoft.Exchange.Configuration.Tasks.ManagementObjectNotFoundException|The specified mailbox doesn''t exist.'; [pscustomobject]@{ MailboxState = $E; Delegations = $E; AddIns = $E } }
        Push-BECRun -Item $script:Item
        $R = $script:Saved.Results
        $R.Completeness.MailboxState.Skipped | Should -BeTrue
        $R.Completeness.Delegations.Skipped | Should -BeTrue
        $R.Completeness.MailboxState.Requirement | Should -Match 'no Exchange Online mailbox'
        $script:Saved.Properties.Status | Should -Be 'Completed'
    }

    It 'flags an inbox rule that forwards externally, deletes, and scopes to no conditions' {
        Mock New-ExoRequest {
            switch ($cmdlet) {
                'Get-AdminAuditLogConfig' { [pscustomobject]@{ UnifiedAuditLogIngestionEnabled = $true } }
                'Get-InboxRule' { [pscustomobject]@{ Name = 'auto'; Identity = 'r9'; Enabled = $true; ForwardTo = @('attacker@evil.example'); DeleteMessage = $true } }
                'Get-MailboxJunkEmailConfiguration' { [pscustomobject]@{ TrustedSendersAndDomains = @(); BlockedSendersAndDomains = @() } }
                'Get-AcceptedDomain' { [pscustomobject]@{ DomainName = 'contoso.com' } }
                default { @() }
            }
        }
        Push-BECRun -Item ($script:Item + @{ Scope = 'Full' })
        $Rule = @($script:Saved.Results.NewRules)[0]
        $Rule.Suspicious | Should -BeTrue
        $Rule.Risk | Should -Be 'High'
        $Rule.RiskReasons | Should -Contain 'Forwards or redirects mail to an external address'
        $Rule.RiskReasons | Should -Contain 'Deletes messages'
        $Rule.RiskReasons | Should -Contain 'Acts on all incoming mail'
    }
}
