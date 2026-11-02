BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-GraphBulkRequest { param($Requests, $tenantid, $asapp, $Version, $NoPaginateIds) }
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results) }
    function Get-CIPPBecMailActivity { param($TenantFilter, $UserPrincipalName, $StartDate, $EndDate, $Heuristics, $Anchor) }
    function Invoke-CIPPBecIPAnalysis { param($TenantFilter, $UserId, $UserPrincipalName, $Results, $Heuristics, $WindowStart, $UsageLocation, $Anchor, $Baseline, $KnownPeers, $Overrides, $ExtraPeers, $TechnicianIPs) }
    function Get-CIPPBecAttackerActivity { param($TenantFilter, $UserPrincipalName, $StartDate, $EndDate, $Heuristics, $Verdicts, $SignIns, $NonInteractiveSignIns, $MailRecords, $SharingChanges, $KnownSubjects, $Anchor) }
    function Get-CIPPBecDelegatedAccess { param($TenantFilter, $UserPrincipalName, $UserDisplayName, $PermissionChanges, $MailActivity, $AttackerMail) }
    function Get-CIPPBecBlastRadius { param($TenantFilter, $UserId, $UserPrincipalName, $Verdicts, $Peers, $StartDate, $EndDate, $Heuristics, $Anchor) }
    function Start-CIPPBecIPReviewJob { param($TenantFilter, $CaseId, $Overrides, $CorrelateUserIds, $UserPrincipalName, $Headers) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TaskId, $TenantFilter) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-NormalizedError { param($message) $message }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    $env:CIPPRootPath = $RepoRoot
    foreach ($File in @('ConvertTo-CIPPODataFilterValue.ps1', 'Authentication/ConvertTo-CIPPIPRange.ps1', 'BEC/ConvertTo-CIPPBecHostAddress.ps1', 'BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Get-CIPPBecHeuristics.ps1', 'BEC/Get-CIPPBecErrorInfo.ps1', 'BEC/Get-CIPPBecScore.ps1', 'BEC/Set-CIPPBecIPVerdictStamp.ps1', 'BEC/Get-CIPPBecCorrelatedUserPeers.ps1', 'BEC/Invoke-CIPPBecIPReview.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECIPReview.ps1' | Select-Object -First 1).FullName

    function New-Request { param($Body) [pscustomobject]@{ Params = [pscustomobject]@{ CIPPEndpoint = 'ExecBECIPReview' }; Headers = $null; Query = $null; Body = [pscustomobject]$Body } }
    function New-Case {
        [pscustomobject]@{
            UserId = 'u1'; UserPrincipalName = 'victim@contoso.com'; DisplayName = 'Victim'; Status = 'Completed'
            Results = [pscustomobject]@{
                ExtractedAt        = '2026-09-23T00:00:00Z'
                AnalysisWindowDays = 7
                LocationAnalysis   = [pscustomobject]@{ UsageLocation = 'AU' }
                SuspectUserSignIns = @([pscustomobject]@{ IPAddress = '198.51.100.7' }, [pscustomobject]@{ IPAddress = '203.0.113.10' })
                IPBaseline         = [pscustomobject]@{ Successful = 40 }
                IPPeers            = @([pscustomobject]@{ IP = '198.51.100.7'; OtherUsersBefore = 0 })
                IPVerdicts         = @([pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'Unknown' })
                IPReviewHistory    = @([pscustomobject]@{ At = 'earlier'; By = 'someone' })
                Completeness       = [pscustomobject]@{ SignIns = [pscustomobject]@{ Complete = $true } }
                MailboxPermissionChanges = @()
                SharingChanges     = @()
            }
        }
    }
}

AfterAll { $env:CIPPRootPath = $null }

Describe 'Get-CIPPBecCorrelatedUserPeers' {
    It 'keeps only the addresses of the case, split into before and only in the window' {
        Mock New-GraphBulkRequest {
            @(
                [pscustomobject]@{ id = 'i0'; status = 200; body = [pscustomobject]@{ value = @(
                            [pscustomobject]@{ ipAddress = '203.0.113.10'; userPrincipalName = 'colleague@contoso.com'; createdDateTime = '2026-09-01T00:00:00Z' }
                            [pscustomobject]@{ ipAddress = '192.0.2.99'; userPrincipalName = 'colleague@contoso.com'; createdDateTime = '2026-09-01T00:00:00Z' }
                        ) } }
                [pscustomobject]@{ id = 'n0'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ ipAddress = '198.51.100.7'; userPrincipalName = 'colleague@contoso.com'; createdDateTime = '2026-09-20T00:00:00Z' }) } }
            )
        }
        $Peers = Get-CIPPBecCorrelatedUserPeers -TenantFilter 'contoso.com' -UserIds @('11111111-1111-1111-1111-111111111111') -IPs @('203.0.113.10', '198.51.100.7') -StartDate '2026-08-15' -WindowStart '2026-09-16'
        $Peers.ContainsKey('192.0.2.99') | Should -BeFalse
        $Peers['203.0.113.10'].OtherUsersBefore | Should -Be 1
        $Peers['198.51.100.7'].OtherUsersInWindowOnly | Should -Be 1
    }
}

Describe 'Invoke-CIPPBecIPReview' {
    BeforeEach {
        Mock Get-CIPPBecReport { New-Case }
        Mock Set-CIPPBecReport { $script:Saved = @{ Results = $Results; Properties = $Properties } }
        Mock Get-CIPPBecMailActivity { $R = New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Operation = 'MailItemsAccessed'; ClientIP = '198.51.100.7'; Count = 4 }); $R | Add-Member -NotePropertyName Summary -NotePropertyValue ([pscustomobject]@{ Records = 4 }) -Force; $R | Add-Member -NotePropertyName Records -NotePropertyValue @([pscustomobject]@{ AuditData = [pscustomobject]@{ Operation = 'MailItemsAccessed' } }) -Force; $R }
        Mock Invoke-CIPPBecIPAnalysis {
            $script:AnalysisArgs = @{ Overrides = $Overrides; Baseline = $Baseline; KnownPeers = $KnownPeers; ExtraPeers = $ExtraPeers; WindowStart = $WindowStart; TechnicianIPs = $TechnicianIPs }
            [pscustomobject]@{
                Baseline = New-CIPPBecCollectorResult -Data $Baseline; Guidance = New-CIPPBecCollectorResult -Data @(); PeersResult = New-CIPPBecCollectorResult -Data @()
                Peers = @{}; Geo = @{}; Events = @()
                Verdicts = @([pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'Compromised'; SuccessfulSignIns = 1; Activities = 4 })
            }
        }
        Mock Get-CIPPBecAttackerActivity {
            $script:AttackerArgs = @{ MailRecords = $MailRecords; Verdicts = $Verdicts }
            $Mail = New-CIPPBecCollectorResult -Data @([pscustomobject]@{ Operation = 'MailItemsAccessed'; IPVerdict = 'Compromised'; MailboxOwner = 'victim@contoso.com' })
            $Mail | Add-Member -NotePropertyName Summary -NotePropertyValue ([pscustomobject]@{ MessagesOpened = 1 }) -Force
            $Forms = New-CIPPBecCollectorResult -Data @(); $Forms | Add-Member -NotePropertyName Summary -NotePropertyValue $null -Force
            [pscustomobject]@{ Mail = $Mail; Files = (New-CIPPBecCollectorResult -Data @()); LinkUsage = (New-CIPPBecCollectorResult -Data @()); Forms = $Forms }
        }
        Mock Get-CIPPBecDelegatedAccess { New-CIPPBecCollectorResult -Data @() }
        Mock Get-CIPPBecBlastRadius { $script:BlastVerdicts = $Verdicts; New-CIPPBecCollectorResult -Data @([pscustomobject]@{ UserPrincipalName = 'cfo@contoso.com'; Reached = $true }) }
        Mock New-GraphBulkRequest { @() }
        $script:Steps = [System.Collections.Generic.List[object]]::new()
        Mock Set-CIPPAsyncDeploymentStep { $script:Steps.Add(@{ Index = $StepIndex; Status = $StepStatus; Message = $Message }) }
        Mock Set-CIPPAsyncDeploymentStatus { $script:FinalStatus = $Status }
        Mock New-CIPPAsyncDeployment { $JobId }
        Mock Write-LogMessage { }
    }

    It 're-judges with the overrides, the stored baseline and peers, and replaces only the address-dependent sections' {
        $Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tech@msp.com"}')); 'x-forwarded-for' = '192.0.2.77:51000, 10.0.0.1' }
        $Message = Invoke-CIPPBecIPReview -TenantFilter 'contoso.com' -CaseId 'BEC-1' -Overrides @([pscustomobject]@{ IP = '198.51.100.0/24'; Verdict = 'Compromised'; Note = 'AiTM proxy' }, [pscustomobject]@{ IP = '203.0.113.10'; Verdict = 'Auto' }) -DeploymentId 'job-1' -Headers $Headers
        $Message | Should -Match 'threat level'
        @($script:AnalysisArgs.Overrides).Count | Should -Be 1 -Because 'Auto means no override'
        $script:AnalysisArgs.Overrides[0].Range | Should -Be '198.51.100.0/24'
        $script:AnalysisArgs.Baseline.Successful | Should -Be 40
        $script:AnalysisArgs.KnownPeers[0].IP | Should -Be '198.51.100.7'
        ([datetime]$script:AnalysisArgs.WindowStart).ToUniversalTime().ToString('yyyy-MM-dd') | Should -Be '2026-09-16' -Because 'the case keeps its original window'
        @($script:AttackerArgs.MailRecords).Count | Should -Be 1 -Because 'the fresh mailbox records feed the detail pass'
        $R = $script:Saved.Results
        $R.IPVerdicts[0].Verdict | Should -Be 'Compromised'
        $R.IPOverrides[0].Note | Should -Be 'AiTM proxy'
        $script:BlastVerdicts[0].Verdict | Should -Be 'Compromised' -Because 'the blast radius follows the re-judged verdicts'
        $R.BlastRadius[0].UserPrincipalName | Should -Be 'cfo@contoso.com'
        $R.SuspectUserSignIns[0].IPVerdict | Should -Be 'Compromised'
        $R.IPReviewHistory.Count | Should -Be 2
        $R.IPReviewHistory[-1].By | Should -Be 'tech@msp.com'
        # the reviewer's address (first x-forwarded-for hop, port stripped) joins the case's technicians
        $script:AnalysisArgs.TechnicianIPs[0].IP | Should -Be '192.0.2.77'
        $script:AnalysisArgs.TechnicianIPs[0].By | Should -Be 'tech@msp.com'
        $R.IPTechnicians[0].IP | Should -Be '192.0.2.77'
        $R.Completeness.SignIns.Complete | Should -BeTrue -Because 'sections the review does not touch keep their markers'
        $R.Completeness.AttackerMailActivity.Complete | Should -BeTrue
        $script:Saved.Properties.Level | Should -Not -BeNullOrEmpty
        $script:Saved.Properties.LastIPReviewAt | Should -Not -BeNullOrEmpty
        @($script:Steps | Where-Object Status -EQ 'succeeded').Index | Should -Be @(0..5)
        $script:FinalStatus | Should -Be 'succeeded'
    }

    It 'correlates chosen accounts across the addresses of the case' {
        Mock Get-CIPPBecCorrelatedUserPeers { $script:CorrelateArgs = @{ UserIds = $UserIds; IPs = $IPs }; @{ '198.51.100.7' = [pscustomobject]@{ IP = '198.51.100.7'; OtherUsersBefore = 3 } } }
        $null = Invoke-CIPPBecIPReview -TenantFilter 'contoso.com' -CaseId 'BEC-1' -CorrelateUserIds @('c1', 'c2')
        @($script:CorrelateArgs.UserIds) | Should -Be @('c1', 'c2')
        @($script:CorrelateArgs.IPs | Sort-Object) | Should -Be @('198.51.100.7', '203.0.113.10')
        $script:AnalysisArgs.ExtraPeers['198.51.100.7'].OtherUsersBefore | Should -Be 3
    }

    It 'fails the step that broke and leaves the case untouched' {
        Mock Invoke-CIPPBecIPAnalysis { throw 'Graph 503' }
        { Invoke-CIPPBecIPReview -TenantFilter 'contoso.com' -CaseId 'BEC-1' -DeploymentId 'job-1' } | Should -Throw '*Graph 503*'
        ($script:Steps | Where-Object Status -EQ 'failed').Index | Should -Be 3
        $script:FinalStatus | Should -Be 'failed'
        Should -Invoke Set-CIPPBecReport -Times 0
    }

    It 'refuses a case that has not completed' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Running' } }
        { Invoke-CIPPBecIPReview -TenantFilter 'contoso.com' -CaseId 'BEC-1' } | Should -Throw '*not a completed investigation*'
    }
}

Describe 'Invoke-ExecBECIPReview' {
    BeforeEach {
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Completed'; UserPrincipalName = 'victim@contoso.com' } }
        Mock Start-CIPPBecIPReviewJob { 'job-1' }
        Mock Write-LogMessage { }
    }

    It 'validates and normalises the overrides, keeps the chosen accounts, and returns the DeploymentId' {
        $Response = Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Overrides = @([pscustomobject]@{ IP = ' 198.51.100.0/24 '; Verdict = [pscustomobject]@{ value = 'Compromised' }; Note = 'proxy' }, [pscustomobject]@{ IP = '203.0.113.10'; Verdict = 'Auto' }); CorrelateUsers = @([pscustomobject]@{ value = 'c1'; label = 'Colleague' }, 'c1') }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.DeploymentId | Should -Be 'job-1'
        Should -Invoke Start-CIPPBecIPReviewJob -Times 1 -ParameterFilter { @($Overrides).Count -eq 1 -and $Overrides[0].IP -eq '198.51.100.0/24' -and $Overrides[0].Verdict -eq 'Compromised' -and (@($CorrelateUserIds) -join ',') -eq 'c1' -and $UserPrincipalName -eq 'victim@contoso.com' }
    }

    It 'refuses a re-run when no verdict changed and no account is to be correlated' {
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Completed'; Results = [pscustomobject]@{ IPOverrides = @([pscustomobject]@{ Range = '198.51.100.0/24'; Verdict = 'Compromised'; Note = 'old note' }) } } }
        $Same = Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Overrides = @([pscustomobject]@{ IP = '198.51.100.0/24'; Verdict = 'Compromised'; Note = 'reworded' }) }) -TriggerMetadata $null
        $Same.StatusCode | Should -Be 400
        $Same.Body.Results[0].resultText | Should -Match 'Nothing changed'
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Completed'; Results = [pscustomobject]@{ IPOverrides = @() } } }
        $AllAuto = Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Overrides = @([pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'Auto' }) }) -TriggerMetadata $null
        $AllAuto.StatusCode | Should -Be 400 -Because 'all Auto is what the case already ran with'
        $AllAuto.Body.Results[0].resultText | Should -Match 'at least one address'
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Completed'; Results = [pscustomobject]@{ IPOverrides = @([pscustomobject]@{ Range = '198.51.100.7'; Verdict = 'Safe' }) } } }
        (Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Overrides = @([pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'Auto' }) }) -TriggerMetadata $null).StatusCode | Should -Be 400 -Because 'going back to all Auto is not a re-run either'
        Should -Invoke Start-CIPPBecIPReviewJob -Times 0
        (Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; CorrelateUsers = @('c1') }) -TriggerMetadata $null).StatusCode | Should -Be 200 -Because 'correlating accounts is a change'
    }

    It 'rejects an invalid address or verdict, an unknown case and an unfinished one without queueing' {
        (Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Overrides = @([pscustomobject]@{ IP = 'example.com'; Verdict = 'Safe' }) }) -TriggerMetadata $null).StatusCode | Should -Be 400
        (Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1'; Overrides = @([pscustomobject]@{ IP = '198.51.100.7'; Verdict = 'Maybe' }) }) -TriggerMetadata $null).StatusCode | Should -Be 400
        Mock Get-CIPPBecReport { $null }
        (Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-9' }) -TriggerMetadata $null).StatusCode | Should -Be 404
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Running' } }
        (Invoke-ExecBECIPReview -Request (New-Request @{ tenantFilter = 'contoso.com'; CaseId = 'BEC-1' }) -TriggerMetadata $null).StatusCode | Should -Be 400
        Should -Invoke Start-CIPPBecIPReviewJob -Times 0
    }
}
