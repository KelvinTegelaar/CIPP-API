function Invoke-CIPPBecIPReview {
    <#
    .SYNOPSIS
        Re-judges a BEC case's IP addresses with the investigator's input and re-reads what depends on them.
    .DESCRIPTION
        The background half of ExecBECIPReview. For a completed case it keeps the original window and
        everything that does not depend on the verdicts, and replaces what does:
        - the investigator's overrides (Safe / Compromised per address or CIDR range) become the case's
          IPOverrides and decide those addresses outright;
        - chosen accounts are correlated (Get-CIPPBecCorrelatedUserPeers) and added to the peers;
        - the address lists are re-read, so an entry just added to CIPP's IP allow/block list counts;
        - mailbox activity is re-read (its raw records feed the detail pass), the verdicts are
          re-judged with the stored baseline and peers, and the attacker activity and delegated
          mailboxes are re-collected;
        - the rows are re-stamped, the score recomputed, and the review appended to IPReviewHistory.
        Progress is reported per step on the DeploymentId row, like containment.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The BEC case (run) to review.
    .PARAMETER Overrides
        { IP (address or CIDR range), Verdict (Safe|Compromised), Note } - the complete set for the case.
    .PARAMETER CorrelateUserIds
        Object ids of accounts whose sign-ins to correlate with the case's addresses.
    .PARAMETER DeploymentId
        Live-progress job id.
    .PARAMETER Headers
        The requesting user's headers (for logging and the review history).
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [object[]]$Overrides = @(),
        [string[]]$CorrelateUserIds = @(),
        [string]$DeploymentId,
        $Headers,
        [string]$APIName = 'BECIPReview'
    )

    $StepTitles = @('Loading the case', 'Correlating the chosen accounts', 'Re-reading mailbox activity', 'Re-judging the IP addresses', 'Re-reading attacker activity and delegated mailboxes', 'Scoring and saving')
    $Name = $CaseId
    $Step = { param($Index, $Status, $Message) if ($DeploymentId) { Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $Name -StepIndex $Index -StepStatus $Status -Message ([string]$Message) } }
    if ($DeploymentId) {
        try {
            $null = New-CIPPAsyncDeployment -JobId $DeploymentId -Names @($Name) -StepTitles $StepTitles -Source 'BECIPReview' -TenantFilter $TenantFilter
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Name -Status 'running'
        } catch { Write-Information "BEC IP review: progress unavailable: $($_.Exception.Message)" }
    }
    if (-not $PSCmdlet.ShouldProcess("$TenantFilter/$CaseId", 'Re-judge the case IP addresses')) { return }

    $Current = 0
    try {
        & $Step 0 'running' 'In progress'
        $Heuristics = Get-CIPPBecHeuristics
        $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
        if (-not $Run -or $Run.Status -ne 'Completed' -or -not $Run.Results) { throw "Case $CaseId is not a completed investigation in $TenantFilter" }
        $Results = $Run.Results
        $UserName = [string]($Run.UserPrincipalName ?? $Results.UserPrincipalName)
        $UserId = [string]$Run.UserId
        $WindowDays = [int]($Results.AnalysisWindowDays ?? $Heuristics.window.days ?? 7)
        $EndDate = ([datetime]$Results.ExtractedAt).ToUniversalTime()
        $StartDate = $EndDate.AddDays(-$WindowDays)
        $BaselineStart = $StartDate.AddDays(-[int]($Heuristics.baseline.days ?? 30))
        $UsageLocation = [string]$Results.LocationAnalysis.UsageLocation
        # the technicians who ran or reviewed the case: the reviewer's own address (first x-forwarded-for
        # hop of the stored request headers) joins the ones already on the case
        $ReviewerIP = ConvertTo-CIPPBecHostAddress -Address ([string](([string]$Headers.'x-forwarded-for' -split ',')[0])).Trim()
        $ReviewerName = if ($Headers -and $Headers.'x-ms-client-principal') { try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null } } else { $null }
        $TechnicianIPs = @(
            @($Results.IPTechnicians | Where-Object { $_ -and $_.IP })
            if ($ReviewerIP -and $ReviewerIP -notin @($Results.IPTechnicians.IP)) { [pscustomobject]@{ IP = $ReviewerIP; By = [string]$ReviewerName } }
        )
        $CaseOverrides = @(foreach ($Override in @($Overrides | Where-Object { $_ })) {
                $Verdict = [string]($Override.Verdict.value ?? $Override.Verdict)
                if ($Verdict -notin @('Safe', 'Compromised')) { continue }
                [pscustomobject]@{ Range = ConvertTo-CIPPIPRange -Value ([string]($Override.IP ?? $Override.Range)); Verdict = $Verdict; Note = [string]$Override.Note }
            })
        $Completeness = $Results.Completeness
        if (-not $Completeness) { $Completeness = [pscustomobject]@{}; $Results | Add-Member -NotePropertyName 'Completeness' -NotePropertyValue $Completeness -Force }
        $Mark = {
            param($MarkerName, $Result)
            $Info = if ($Result.Error) { Get-CIPPBecErrorInfo -Message ([string]$Result.Error) } else { $null }
            $Completeness | Add-Member -NotePropertyName $MarkerName -NotePropertyValue ([pscustomobject]@{
                    Complete    = [bool]$Result.Complete
                    Cap         = $Result.Cap
                    Error       = if ($Info) { $Info.Message } else { $Result.Error }
                    Skipped     = [bool]($Result.Skipped -or ($Info -and $Info.Skipped))
                    Requirement = if ($Result.Requirement) { $Result.Requirement } elseif ($Info) { $Info.Requirement } else { $null }
                    Count       = [int]$Result.Count
                }) -Force
        }
        $Set = { param($Property, $Value) $Results | Add-Member -NotePropertyName $Property -NotePropertyValue $Value -Force }
        & $Step 0 'succeeded' "Case $CaseId for $UserName"

        $Current = 1
        & $Step 1 'running' 'In progress'
        $ExtraPeers = @{}
        if (@($CorrelateUserIds | Where-Object { $_ }).Count -gt 0) {
            $CaseIPs = @(@($Results.IPVerdicts.IP) + @($Results.SuspectUserSignIns.IPAddress) + @($Results.NonInteractiveSignIns.IPAddress) | Where-Object { $_ } | ForEach-Object { ConvertTo-CIPPBecHostAddress -Address ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
            $ExtraPeers = Get-CIPPBecCorrelatedUserPeers -TenantFilter $TenantFilter -UserIds $CorrelateUserIds -IPs $CaseIPs -StartDate $BaselineStart -WindowStart $StartDate
            & $Step 1 'succeeded' "$(@($CorrelateUserIds).Count) account(s) correlated; $($ExtraPeers.Count) of the case's addresses shared"
        } else {
            & $Step 1 'succeeded' 'No accounts chosen'
        }

        $Current = 2
        & $Step 2 'running' 'In progress'
        $Activity = try { Get-CIPPBecMailActivity -TenantFilter $TenantFilter -UserPrincipalName $UserName -StartDate $StartDate -EndDate $EndDate -Heuristics $Heuristics -Anchor $UserName } catch {
            New-CIPPBecCollectorResult -Data @() -Error "Mailbox activity failed: $((Get-NormalizedError -message $_.Exception.Message))"
        }
        & $Mark 'MailActivity' $Activity
        & $Set 'MailActivity' @($Activity.Data)
        & $Set 'MailActivitySummary' $Activity.Summary
        $MailRecords = @($Activity.Records | Where-Object { $_ })
        & $Step 2 'succeeded' "$(@($Activity.Data).Count) activity group(s), $($MailRecords.Count) record(s)"

        $Current = 3
        & $Step 3 'running' 'In progress'
        $Analysis = Invoke-CIPPBecIPAnalysis -TenantFilter $TenantFilter -UserId $UserId -UserPrincipalName $UserName -Results $Results -Heuristics $Heuristics -WindowStart $StartDate -UsageLocation $UsageLocation -Anchor $UserName -Baseline $Results.IPBaseline -KnownPeers @($Results.IPPeers) -Overrides $CaseOverrides -ExtraPeers $ExtraPeers -TechnicianIPs $TechnicianIPs
        & $Mark 'SignInBaseline' $Analysis.Baseline
        & $Mark 'IPGuidance' $Analysis.Guidance
        & $Mark 'IPPeers' $Analysis.PeersResult
        & $Mark 'IPVerdicts' ([pscustomobject]@{ Complete = $true; Count = @($Analysis.Verdicts).Count })
        $Verdicts = @($Analysis.Verdicts)
        & $Set 'IPVerdicts' $Verdicts
        & $Set 'IPGuidance' @($Analysis.Guidance.Data)
        & $Set 'IPPeers' @($Analysis.Peers.Values)
        & $Set 'IPOverrides' @($CaseOverrides)
        & $Set 'IPTechnicians' @($TechnicianIPs)
        Set-CIPPBecIPVerdictStamp -Results $Results -Verdicts $Verdicts
        $Attackers = @($Verdicts | Where-Object { $_.Verdict -in @('Compromised', 'LikelyAttacker') }).Count
        & $Step 3 'succeeded' "$($Verdicts.Count) address(es): $Attackers attacker, $(@($Verdicts | Where-Object { $_.Verdict -in @('Suspicious', 'Unknown') }).Count) suspicious or unknown"

        $Current = 4
        & $Step 4 'running' 'In progress'
        $Attacker = Get-CIPPBecAttackerActivity -TenantFilter $TenantFilter -UserPrincipalName $UserName -StartDate $StartDate -EndDate $EndDate -Heuristics $Heuristics -Verdicts $Verdicts -SignIns @($Results.SuspectUserSignIns) -NonInteractiveSignIns @($Results.NonInteractiveSignIns) -MailRecords $MailRecords -SharingChanges @($Results.SharingChanges) -Anchor $UserName
        & $Mark 'AttackerMailActivity' $Attacker.Mail
        & $Mark 'AttackerFileActivity' $Attacker.Files
        & $Mark 'LinkUsage' $Attacker.LinkUsage
        & $Mark 'FormsActivity' $Attacker.Forms
        & $Set 'AttackerMailActivity' @($Attacker.Mail.Data)
        & $Set 'AttackerMailSummary' $Attacker.Mail.Summary
        & $Set 'AttackerFileActivity' @($Attacker.Files.Data)
        & $Set 'AttackerFileSummary' $Attacker.Files.Summary
        & $Set 'LinkUsage' @($Attacker.LinkUsage.Data)
        & $Set 'FormsActivity' @($Attacker.Forms.Data)
        & $Set 'FormsSummary' $Attacker.Forms.Summary
        $Delegated = Get-CIPPBecDelegatedAccess -TenantFilter $TenantFilter -UserPrincipalName $UserName -UserDisplayName ([string]$Run.DisplayName) -PermissionChanges @($Results.MailboxPermissionChanges) -MailActivity @($Activity.Data) -AttackerMail @($Attacker.Mail.Data)
        & $Mark 'DelegatedAccess' $Delegated
        & $Set 'DelegatedAccess' @($Delegated.Data)
        $Blast = Get-CIPPBecBlastRadius -TenantFilter $TenantFilter -UserId $UserId -UserPrincipalName $UserName -Verdicts $Verdicts -Peers $Analysis.Peers -StartDate $StartDate -EndDate $EndDate -Heuristics $Heuristics -Anchor $UserName
        & $Mark 'BlastRadius' $Blast
        & $Set 'BlastRadius' @($Blast.Data)
        & $Step 4 'succeeded' "$(@($Attacker.Mail.Data).Count) mail row(s), $(@($Attacker.Files.Data).Count) file row(s), $(@($Attacker.Forms.Data).Count) Forms action(s), $(@($Delegated.Data).Count) delegated mailbox(es), $(@($Blast.Data | Where-Object { $_.Reached }).Count) other account(s) reached"

        $Current = 5
        & $Step 5 'running' 'In progress'
        $By = if ($Headers -and $Headers.'x-ms-client-principal') { try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' } } else { 'CIPP' }
        $History = @(@($Results.IPReviewHistory | Where-Object { $_ }) + @([pscustomobject]@{
                    At              = (Get-Date).ToUniversalTime().ToString('o')
                    By              = [string]$By
                    Overrides       = @($CaseOverrides)
                    CorrelatedUsers = @($CorrelateUserIds | Where-Object { $_ })
                    AttackerIPs     = $Attackers
                }))
        & $Set 'IPReviewHistory' $History
        & $Set 'UserPrincipalName' $UserName
        $Score = Get-CIPPBecScore -Results $Results -Heuristics $Heuristics
        & $Set 'Score' $Score
        $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Results $Results -Properties @{
            Score           = [int]$Score.Value
            Level           = [string]$Score.Level
            LastIPReviewAt  = (Get-Date).ToUniversalTime().ToString('o')
            IncompleteCount = @($Completeness.PSObject.Properties | Where-Object { -not $_.Value.Complete }).Count
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Reviewed the IP addresses of BEC case $CaseId for $UserName`: $Attackers attacker address(es), threat level $($Score.Level) ($($Score.Value))" -sev 'Info'
        & $Step 5 'succeeded' "Threat level $($Score.Level) ($($Score.Value))"
        if ($DeploymentId) { Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Name -Status 'succeeded' }
        return "Reviewed the IP addresses of case $CaseId`: $Attackers attacker address(es), threat level $($Score.Level) ($($Score.Value))"
    } catch {
        $Message = Get-NormalizedError -message $_.Exception.Message
        & $Step $Current 'failed' $Message
        if ($DeploymentId) { Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Name -Status 'failed' }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC IP review of case $CaseId failed: $Message" -sev 'Error'
        throw
    }
}
