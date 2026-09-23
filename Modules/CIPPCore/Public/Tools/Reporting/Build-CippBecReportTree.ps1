function Build-CippBecReportTree {
    <#
    .SYNOPSIS
        Compose the BEC (Business Email Compromise) analysis report as a component tree - the server
        port of BECRemediationReportButton's BECRemediationReportDocument.
    .DESCRIPTION
        Returns @{ Blocks; Variables }: the content blocks plus the cover/footer report variables. The
        cover names the compromised user rather than the tenant. Detail callouts use -Lines so each
        label/value line is a tight line break.

        The report leads with an executive intelligence section (results roll-up, findings by attacker
        objective, evidence-driven priority actions, an order-of-events timeline and any containment
        already run), then educational context, the per-check detail (Checks 1-21), and recommendations
        and compliance. Every derived value mirrors the client renderer and the case workspace helpers
        (bec-objectives / bec-timeline) so the PDF and the on-screen case agree. The threat level is read
        from the server-computed Score on the run; the analysis window is AnalysisWindowDays.
    .PARAMETER UserData
        The investigated user: displayName, userPrincipalName.
    .PARAMETER BecData
        The completed BEC results payload (from BecResults), with a .Run block attached carrying the
        run's CaseId and containment history (as the client receives it from execBECCheck).
    .PARAMETER TenantName
        The tenant the user belongs to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$UserData, [Parameter(Mandatory)]$BecData, [string]$TenantName, [ValidateSet('full', 'summary')][string]$Variant = 'full')

    # 'summary' = the executive pages only (cover + Executive Summary), for a C-suite reader; 'full' =
    # every page. Mirrors the client BECRemediationReportDocument variant.
    $isSummary = $Variant -eq 'summary'
    $bec = $BecData
    $loc = $bec.LocationAnalysis
    $ana = $bec.SentMessageAnalysis
    $windowDays = if ($bec.AnalysisWindowDays) { [int]$bec.AnalysisWindowDays } else { 7 }

    # -- formatting/utility helpers --
    function Cnt($x) { if ($null -eq $x) { return 0 }; @($x).Count }
    function AsInt($v) { if ($null -eq $v) { return 0 }; try { [int]$v } catch { 0 } }
    function ToDate($v) { if (-not $v) { return $null }; try { [datetime]$v } catch { $null } }
    function FmtDate($d) {
        if (-not $d) { return 'N/A' }
        try { return ([datetime]$d).ToString('MMM d, yyyy, hh:mm tt', [Globalization.CultureInfo]::InvariantCulture) } catch { return "$d" }
    }
    function FmtSafelist($v) {
        if (-not $v) { return 'unchanged' }
        if ($v -is [array]) { $j = ($v -join ', '); if ($j) { return $j } else { return 'unchanged' } }
        return "$v"
    }
    function CleanStr($v) { $t = "$v".Trim(); if ($t.Length -gt 0) { $t } else { $null } }
    function JoinDetail { param([object[]]$Parts) (@($Parts | ForEach-Object { CleanStr $_ } | Where-Object { $_ })) -join ' - ' }
    # one host is one source: audit addresses carry a per-connection port (mirrors the client hostIp)
    function HostIp($v) {
        $t = CleanStr $v
        if (-not $t) { return $null }
        ($t -replace '^(\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+)(?::\d+)?$', '$1') -replace '[\[\]]', ''
    }
    function ListNames([object[]]$Names, [int]$Max = 3) {
        $All = @($Names | Where-Object { $_ })
        (@($All | Select-Object -First $Max) -join ', ') + $(if ($All.Count -gt $Max) { " and $($All.Count - $Max) more" } else { '' })
    }
    # plain-English counts for the statements a non-technical reader sees
    function Plural([int]$N, [string]$One, [string]$Many) { if (-not $Many) { $Many = "${One}s" }; "$N $(if ($N -eq 1) { $One } else { $Many })" }

    # analysis window: windowDays before extraction (mirrors becWindowStart)
    $extractedAt = ToDate $bec.ExtractedAt
    if (-not $extractedAt) { $extractedAt = Get-Date }
    $windowStart = $extractedAt.AddDays(-$windowDays)

    # -- statistics (mirrors the client stats object) --
    $stats = @{
        newRules                       = Cnt $bec.NewRules
        ruleChanges                    = Cnt $bec.InboxRuleChanges
        newUsers                       = Cnt $bec.NewUsers
        newApps                        = Cnt $bec.AddedApps
        permissionChanges              = Cnt $bec.MailboxPermissionChanges
        permissionChangesTargetingUser = Cnt @($bec.MailboxPermissionChanges | Where-Object { $_.TargetsSuspect -eq $true })
        mfaDevices                     = Cnt $bec.MFADevices
        passwordChanges                = Cnt $bec.ChangedPasswords
        sentMessages                   = Cnt $bec.SentMessages
        trustedSenders                 = Cnt $bec.TrustedSenders
        blockedSenders                 = Cnt $bec.BlockedSenders
        safelistChanges                = Cnt $bec.SafelistChanges
        sharingChanges                 = Cnt $bec.SharingChanges
        anonymousLinks                 = Cnt @($bec.SharingChanges | Where-Object { "$($_.Operation)".StartsWith('AnonymousLink') })
        intuneDevices                  = Cnt $bec.IntuneDevices
        signIns                        = Cnt $bec.SuspectUserSignIns
        sentTotalMessages              = AsInt $ana.TotalMessages
        sentTotalRecipients            = AsInt $ana.TotalRecipients
        repeatedSubjects               = AsInt $ana.FlaggedSubjectCount
        sendBursts                     = Cnt $ana.Bursts
        massMailFlagged                = ($ana.Flagged -eq $true)
        maliciousApps                  = (Cnt @($bec.AddedApps | Where-Object { $_.MaliciousMatch })) + (Cnt $bec.MaliciousSPs)
        foreignSignIns                 = AsInt $loc.ForeignSignInCount
        foreignSuccessfulSignIns       = AsInt $loc.ForeignSuccessfulSignInCount
        foreignSentMessages            = AsInt $loc.ForeignSentMessageCount
    }
    $stats.foreignActivity = (AsInt $loc.ForeignRuleChangeCount) + (AsInt $loc.ForeignSafelistChangeCount) +
    (AsInt $loc.ForeignSharingChangeCount) + (AsInt $loc.ForeignSentMessageCount)
    $stats.recentIntuneDevices = Cnt @($bec.IntuneDevices | Where-Object { $d = ToDate $_.enrolledDateTime; $d -and $d -ge $windowStart })
    $stats.recentMfaDevices = Cnt @($bec.MFADevices | Where-Object { $d = ToDate $_.createdDateTime; $d -and $d -ge $windowStart })

    # successful foreign sign-ins first
    $foreignSignInList = @($bec.SuspectUserSignIns | Where-Object { $_.ForeignLocation -eq $true } |
        Sort-Object -Property @{ Expression = { $_.Status -eq 'Success' }; Descending = $true })
    $sortedIntune = @($bec.IntuneDevices | Sort-Object -Property @{ Expression = { $d = ToDate $_.enrolledDateTime; if ($d) { $d } else { [datetime]0 } }; Descending = $true })

    # -- threat level (server-computed, read from the run's Score) --
    $threatLevel = if ($bec.Score.Level) { "$($bec.Score.Level)" } else { 'Low' }
    $threatValue = AsInt $bec.Score.Value
    $threatColour = @{ High = '#742A2A'; Medium = '#744210'; Low = '#22543D' }[$threatLevel]
    if (-not $threatColour) { $threatColour = '#22543D' }
    $appliedSignals = @($bec.Score.Breakdown | Where-Object { $_.Applied })

    # -- completeness (skipped / partial checks) --
    $completeness = $bec.Completeness
    $completenessEntries = if ($completeness) { @($completeness.PSObject.Properties) } else { @() }
    $skippedCollectors = @($completenessEntries | Where-Object { $_.Value -and $_.Value.Skipped })
    $incompleteCollectors = @($completenessEntries | Where-Object { $_.Value -and $_.Value.Complete -eq $false -and -not $_.Value.Skipped })

    # -- flagged subsets used by the executive section and the deep checks --
    $flaggedDelegations = @($bec.Delegations | Where-Object { $_.Flagged })
    $flaggedGrants = @($bec.UserGrants | Where-Object { $_.Flagged })
    $flaggedTransportChanges = @($bec.TransportRuleChanges | Where-Object { $_.Flagged })
    $flaggedTransportRules = @($bec.TransportRulesFlagged)
    $flaggedAddIns = @($bec.MailboxAddIns | Where-Object { $_.Flagged })
    $receivedFindings = @($bec.ReceivedMailFindings)
    $deliveredThreats = @($bec.DefenderDetections | Where-Object { $_.Delivered })
    $flaggedAudits = @($bec.DirectoryAudits | Where-Object { $_.Flagged })
    $recentRegisteredDevices = @($bec.RegisteredDevices | Where-Object { $_.RegisteredInWindow })
    $foreignNonInteractive = @($bec.NonInteractiveSignIns | Where-Object { $_.ForeignLocation -eq $true -and $_.Status -eq 'Success' })
    $mailActivitySummary = $bec.MailActivitySummary
    $riskState = $bec.RiskState

    # The attacker's addresses and what was done from them. Only an address judged the attacker's
    # (Compromised or LikelyAttacker) counts toward a statement; a Suspicious one is listed in the
    # detail for review, never asserted. The item lists are capped - the evidence export has them all.
    $attackerVerdicts = @('Compromised', 'LikelyAttacker')
    $ipVerdicts = @($bec.IPVerdicts | Where-Object { $_ -and $_.IP })
    $verdictByIp = @{}
    foreach ($v in $ipVerdicts) { $verdictByIp[(HostIp $v.IP)] = "$($v.Verdict)" }
    $attackerIps = @($ipVerdicts | Where-Object { $_.Verdict -in $attackerVerdicts })
    $reviewIps = @($ipVerdicts | Where-Object { $_.Verdict -in $attackerVerdicts -or $_.Verdict -eq 'Suspicious' })
    $attackerCountries = @($attackerIps | ForEach-Object { $_.Country } | Where-Object { $_ } | Select-Object -Unique)
    $attackerMail = @($bec.AttackerMailActivity | Where-Object { $_ -and $_.IPVerdict -in $attackerVerdicts })
    $attackerFiles = @($bec.AttackerFileActivity | Where-Object { $_ -and $_.IPVerdict -in $attackerVerdicts })
    $attackerForms = @($bec.FormsActivity | Where-Object { $_ -and $_.Flagged -eq $true -and $_.IPVerdict -in $attackerVerdicts })
    $attackerFormIds = @($attackerForms | ForEach-Object { $_.FormId } | Where-Object { $_ } | Select-Object -Unique)
    $attackerFormNames = @($attackerForms | ForEach-Object { $_.FormName } | Where-Object { $_ } | Select-Object -Unique)
    $formsReach = @($bec.FormsSummary.Forms | Where-Object { $_ -and $_.FormId -in $attackerFormIds })
    $formResponses = (@($formsReach | ForEach-Object { AsInt $_.Responses }) | Measure-Object -Sum).Sum
    $blastRadius = @($bec.BlastRadius | Where-Object { $_ })
    $reachedAccounts = @($blastRadius | Where-Object { $_.Reached -eq $true })
    $delegatedReached = @($bec.DelegatedAccess | Where-Object { $_ -and $_.Flagged -eq $true })
    $attackerTotals = @{
        opened     = @($attackerMail | Where-Object { $_.Operation -eq 'MailItemsAccessed' -and $_.InternetMessageId } | ForEach-Object { $_.InternetMessageId } | Select-Object -Unique).Count
        synced     = @($attackerMail | Where-Object { $_.Operation -eq 'MailItemsAccessed' -and $_.AccessType -eq 'Sync' } | ForEach-Object { "$($_.MailboxOwner)|$($_.Folder)" } | Select-Object -Unique).Count
        sent       = @($attackerMail | Where-Object { $_.Operation -in @('Send', 'SendAs', 'SendOnBehalf') }).Count
        deleted    = @($attackerMail | Where-Object { $_.Operation -in @('SoftDelete', 'HardDelete', 'MoveToDeletedItems') }).Count
        files      = @($attackerFiles | ForEach-Object { if ($_.Url) { $_.Url } else { $_.File } } | Where-Object { $_ } | Select-Object -Unique).Count
        downloaded = @($attackerFiles | Where-Object { $_.Operation -in @('FileDownloaded', 'FileSyncDownloadedFull') }).Count
    }
    $attackerDid = @(
        if ($attackerTotals.opened) { "opened $(Plural $attackerTotals.opened 'email')" }
        if ($attackerTotals.synced) { "copied $(Plural $attackerTotals.synced 'mail folder') to a desktop client" }
        if ($attackerTotals.sent) { "sent $(Plural $attackerTotals.sent 'email')" }
        if ($attackerTotals.deleted) { "deleted $(Plural $attackerTotals.deleted 'email')" }
        if ($attackerTotals.files) { "opened $(Plural $attackerTotals.files 'file')$(if ($attackerTotals.downloaded) { " ($(Plural $attackerTotals.downloaded 'download'))" })" }
    )
    $attackerReach = @(
        if ($reachedAccounts.Count) { "$(Plural $reachedAccounts.Count 'other account') signed into or used from the same addresses ($(ListNames @($reachedAccounts | ForEach-Object { $_.UserPrincipalName })))" }
        if ($delegatedReached.Count) { "$(Plural $delegatedReached.Count 'other mailbox' 'other mailboxes') reached through this account's access ($(ListNames @($delegatedReached | ForEach-Object { $_.Mailbox })))" }
        if ($attackerFormIds.Count) { "$(Plural $attackerFormIds.Count 'Microsoft Form') created from those addresses (a common phishing lure)$(if ($formResponses) { ", with $(Plural $formResponses 'response')" })" }
    )
    # the three strongest reasons behind a verdict, or the list/investigator that decided it
    function VerdictWhy($v) {
        if ($v.Source -and $v.Source -ne 'Heuristics') { return "$($v.Source)" }
        (@($v.Reasons | Where-Object { (AsInt $_.Weight) -gt 0 } | Sort-Object -Property @{ Expression = { AsInt $_.Weight }; Descending = $true } -Stable | Select-Object -First 3 | ForEach-Object { $_.Text })) -join '; '
    }

    $forwardingAddress = if ($bec.MailboxState.ForwardingSmtpAddress) { "$($bec.MailboxState.ForwardingSmtpAddress)" } elseif ($bec.MailboxState.ForwardingAddress) { "$($bec.MailboxState.ForwardingAddress)" } else { $null }
    $hasForwarding = [bool]($bec.MailboxState.HasForwarding -or $forwardingAddress)

    $upn = $UserData.userPrincipalName
    $usageLoc = $loc.UsageLocation

    # ============================================================================================
    # Findings by attacker objective (the same five-objective lens and flag predicates the case
    # workspace uses - becFindingFlags / becGroupFlagged). Only the per-finding counts feed the bars.
    # ============================================================================================
    $flagCounts = @{
        IPVerdicts               = $attackerIps.Count
        AttackerMailActivity     = $attackerMail.Count
        AttackerFileActivity     = $attackerFiles.Count
        FormsActivity            = Cnt @($bec.FormsActivity | Where-Object { $_.Flagged -eq $true })
        DelegatedAccess          = $delegatedReached.Count
        BlastRadius              = $reachedAccounts.Count
        SuspectUserSignIns       = AsInt $loc.ForeignSuccessfulSignInCount
        NonInteractiveSignIns    = Cnt @($bec.NonInteractiveSignIns | Where-Object { $_.ForeignLocation -eq $true -and $_.Status -eq 'Success' })
        MFADevices               = $stats.recentMfaDevices
        RiskState                = $(if ($riskState.Listed) { 1 } else { 0 })
        RegisteredDevices        = $recentRegisteredDevices.Count
        IntuneDevices            = $stats.recentIntuneDevices
        NewRules                 = Cnt @($bec.NewRules | Where-Object { $_.Suspicious -or (@($_.RiskReasons).Count -gt 0) })
        Delegations              = $flaggedDelegations.Count
        UserGrants               = $flaggedGrants.Count
        MailboxAddIns            = $flaggedAddIns.Count
        AddedApps                = (Cnt @($bec.AddedApps | Where-Object { $_.MaliciousMatch })) + (Cnt $bec.MaliciousSPs)
        MailboxState             = @(if ($bec.MailboxState.HasForwarding) { 1 }; if ($bec.MailboxState.AutoReplyState -and $bec.MailboxState.AutoReplyState -ne 'Disabled') { 1 }).Count
        TrustedSenders           = $stats.safelistChanges
        TransportRuleChanges     = $flaggedTransportChanges.Count
        MailboxPermissionChanges = $stats.permissionChangesTargetingUser
        SentMessages             = $(if ($stats.massMailFlagged) { 1 } else { 0 })
        SharingChanges           = $stats.anonymousLinks
        MailActivity             = $(if ($mailActivitySummary.HardDeleteExceeded) { 1 } else { 0 })
        ReceivedMailFindings     = $receivedFindings.Count + $deliveredThreats.Count
        NewUsers                 = $stats.newUsers
        DirectoryAudits          = $flaggedAudits.Count
    }
    $groupKeys = [ordered]@{
        attacker    = @('IPVerdicts', 'AttackerMailActivity', 'AttackerFileActivity', 'FormsActivity', 'DelegatedAccess')
        access      = @('SuspectUserSignIns', 'NonInteractiveSignIns', 'MFADevices', 'RiskState', 'RegisteredDevices', 'IntuneDevices')
        persistence = @('NewRules', 'Delegations', 'UserGrants', 'MailboxAddIns', 'AddedApps')
        mailflow    = @('MailboxState', 'TrustedSenders', 'TransportRuleChanges', 'MailboxPermissionChanges')
        exfil       = @('SentMessages', 'SharingChanges', 'MailActivity', 'ReceivedMailFindings')
        blast       = @('BlastRadius', 'PartnerActions', 'NewUsers', 'ChangedPasswords', 'DirectoryAudits')
    }
    $objectiveMeta = @{
        attacker    = @{ label = 'Attacker IPs & activity'; colour = '#C53030' }
        access      = @{ label = 'Access'; colour = '#3182CE' }
        persistence = @{ label = 'Persistence'; colour = '#805AD5' }
        mailflow    = @{ label = 'Mail flow'; colour = '#DD6B20' }
        exfil       = @{ label = 'Exfiltration'; colour = '#E53E3E' }
        blast       = @{ label = 'Blast radius'; colour = '#718096' }
    }
    $objectiveData = @(foreach ($id in $groupKeys.Keys) {
            $sum = (@($groupKeys[$id] | ForEach-Object { AsInt $flagCounts[$_] }) | Measure-Object -Sum).Sum
            @{ label = $objectiveMeta[$id].label; value = [int]$sum; colour = $objectiveMeta[$id].colour }
        })
    $totalFindings = (@($objectiveData | ForEach-Object { $_.value }) | Measure-Object -Sum).Sum
    $objectiveMax = [Math]::Max((@($objectiveData | ForEach-Object { $_.value }) | Measure-Object -Maximum).Maximum, 1)

    # ============================================================================================
    # Results roll-up: every check as one row, flagged (with a high-risk sub-count) or clear.
    # ============================================================================================
    $summarySource = @(
        @{ area = 'Attacker network addresses'; count = $attackerIps.Count; danger = @($attackerIps | Where-Object { (AsInt $_.SuccessfulSignIns) -gt 0 -or (AsInt $_.Activities) -gt 0 }).Count }
        @{ area = 'Mail, files & forms touched by the attacker'; count = ($attackerMail.Count + $attackerFiles.Count + $attackerForms.Count); danger = $attackerFormIds.Count }
        @{ area = 'Other accounts & mailboxes reached'; count = ($blastRadius.Count + $delegatedReached.Count); danger = $reachedAccounts.Count }
        @{ area = 'Inbox rules & changes'; count = ($stats.newRules + $stats.ruleChanges) }
        @{ area = 'Mailbox delegations'; count = $flaggedDelegations.Count }
        @{ area = 'Application consents'; count = $flaggedGrants.Count; danger = $flaggedGrants.Count }
        @{ area = 'New / rogue applications'; count = $stats.newApps; danger = $stats.maliciousApps }
        @{ area = 'Mailbox permission changes'; count = $stats.permissionChanges }
        @{ area = 'Transport rules'; count = ($flaggedTransportRules.Count + $flaggedTransportChanges.Count) }
        @{ area = 'Mailbox add-ins'; count = $flaggedAddIns.Count }
        @{ area = 'Forwarding & auto-reply'; count = $(if ($hasForwarding) { 1 } else { 0 }) }
        @{ area = 'Trusted / blocked sender changes'; count = $stats.safelistChanges }
        @{ area = 'Sent mail / mass-mail'; count = $(if ($stats.massMailFlagged) { 1 } else { 0 }) }
        @{ area = 'Received phishing & threats'; count = ($receivedFindings.Count + $deliveredThreats.Count); danger = $deliveredThreats.Count }
        @{ area = 'Sharing links'; count = $stats.sharingChanges; danger = $stats.anonymousLinks }
        @{ area = 'MFA methods (new in window)'; count = $stats.recentMfaDevices }
        @{ area = 'Registered devices (new in window)'; count = $recentRegisteredDevices.Count }
        @{ area = 'Intune devices (new in window)'; count = $stats.recentIntuneDevices }
        @{ area = 'Foreign successful sign-ins'; count = $stats.foreignSuccessfulSignIns; danger = $stats.foreignSuccessfulSignIns }
        @{ area = 'Directory audit events'; count = $flaggedAudits.Count }
        @{ area = 'Identity Protection risk'; count = $(if ($riskState.Listed) { 1 } else { 0 }) }
    )
    $summaryData = @($summarySource | ForEach-Object {
            $danger = AsInt $_.danger
            $flagged = AsInt $_.count
            $result = if ($danger -gt 0) { "$flagged flagged - $danger high-risk" } elseif ($flagged -gt 0) { "$flagged flagged" } else { 'Clear' }
            $tone = if ($danger -gt 0) { 'fail' } elseif ($flagged -gt 0) { 'warn' } else { 'pass' }
            @{ area = $_.area; result = $result; tone = $tone }
        })
    $flaggedAreaCount = @($summaryData | Where-Object { $_.result -ne 'Clear' }).Count

    # ============================================================================================
    # Priority remediation actions, written from what was actually found (mirrors tailoredActions).
    # ============================================================================================
    $isHighOrMed = ($threatLevel -eq 'High' -or $threatLevel -eq 'Medium')
    $ruleNames = (@($bec.NewRules | ForEach-Object { $_.Name } | Where-Object { $_ } | Select-Object -First 3)) -join ', '
    $rogueAppNames = (@(
            @($bec.AddedApps | Where-Object { $_.MaliciousMatch } | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.AppId } })
            @($bec.MaliciousSPs | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.AppId } })
        ) | Where-Object { $_ } | Select-Object -First 3) -join ', '
    $consentNames = (@($flaggedGrants | ForEach-Object { if ($_.ClientDisplayName) { $_.ClientDisplayName } else { $_.ClientAppId } } | Where-Object { $_ } | Select-Object -First 3)) -join ', '

    $tailoredActions = @(
        if ($isHighOrMed) { @{ ids = @('ResetPassword', 'RevokeSessions'); tag = 'Critical'; text = "Reset $(if ($upn) { $upn } else { 'the user' })'s password and revoke all active sessions to cut off any current attacker access." } }
        if ($threatLevel -eq 'High') { @{ ids = @('DisableAccount'); tag = 'Critical'; text = 'Block sign-in for the account until the mailbox and identity are confirmed clean.' } }
        if ($reachedAccounts.Count -gt 0) { @{ tag = 'Critical'; text = "Secure the $($reachedAccounts.Count) other account(s) reached from the attacker's addresses ($(ListNames @($reachedAccounts | ForEach-Object { $_.UserPrincipalName }))): reset, revoke sessions and investigate each one." } }
        if ($flaggedGrants.Count -gt 0 -or $stats.maliciousApps -gt 0) {
            $names = if ($consentNames) { $consentNames } elseif ($rogueAppNames) { $rogueAppNames } else { '' }
            @{ ids = @('RemoveOAuthGrants'); tag = 'Critical'; text = "Revoke $($flaggedGrants.Count + $stats.maliciousApps) risky application consent(s)$(if ($names) { " ($names)" }) - consent survives a password reset." }
        }
        if ($stats.maliciousApps -gt 0) { @{ ids = @('DisableServicePrincipals'); tag = 'Critical'; text = "Disable the catalog-matched rogue application(s)$(if ($rogueAppNames) { " ($rogueAppNames)" }) tenant-wide." } }
        if ($attackerIps.Count -gt 0) { @{ tag = 'High'; text = "Block the $($attackerIps.Count) attacker address(es) ($(ListNames @($attackerIps | ForEach-Object { $_.IP }))) tenant-wide so they cannot be used against any other account." } }
        if ($attackerFormIds.Count -gt 0) { @{ tag = 'High'; text = "Remove the $($attackerFormIds.Count) Microsoft Form(s) built from the attacker's addresses$(if ($attackerFormNames.Count) { " ($(ListNames $attackerFormNames))" }) and warn anyone who responded: confirm phishing and delete each one from its Microsoft Defender alert, or, after the password reset, delete it in Microsoft Forms as the account." } }
        if ($delegatedReached.Count -gt 0) { @{ tag = 'High'; text = "Check the $($delegatedReached.Count) other mailbox(es) reached through this account ($(ListNames @($delegatedReached | ForEach-Object { $_.Mailbox }))) for rules, forwarding and sent mail." } }
        if ($stats.newRules -gt 0 -or $stats.ruleChanges -gt 0) { @{ ids = @('DisableInboxRules'); tag = 'High'; text = "Disable the $($stats.newRules + $stats.ruleChanges) suspicious inbox rule(s)/change(s)$(if ($ruleNames) { " ($ruleNames)" }) that hide replies or auto-forward mail." } }
        if ($hasForwarding) { @{ ids = @('ClearForwarding'); tag = 'High'; text = "Clear mailbox forwarding$(if ($forwardingAddress) { " to $forwardingAddress" }), which silently copies mail out of the tenant." } }
        if ($flaggedDelegations.Count -gt 0) { @{ ids = @('RemoveDelegations'); tag = 'High'; text = "Remove $($flaggedDelegations.Count) flagged mailbox delegation(s) - a delegate keeps access after a reset." } }
        if ($stats.anonymousLinks -gt 0 -or $stats.sharingChanges -gt 0) { @{ ids = @('RemoveSharingLinks'); tag = 'High'; text = "Remove the $($stats.sharingChanges) sharing-link change(s)$(if ($stats.anonymousLinks) { ", including $($stats.anonymousLinks) 'anyone' link(s)" }) and disable OneDrive sharing - anonymous links expose data past any reset." } }
        if ($stats.massMailFlagged) { @{ tag = 'High'; text = "The mailbox sent a mass-mail campaign ($($stats.sentTotalMessages) message(s) to $($stats.sentTotalRecipients) recipient(s)). Scope the wave and warn recipients before anything is purged." } }
        if ($stats.foreignSuccessfulSignIns -gt 0) { @{ tag = 'High'; text = "$($stats.foreignSuccessfulSignIns) successful sign-in(s) from outside the assigned usage location confirm access - treat the account as compromised." } }
        if (($flaggedTransportRules.Count + $flaggedTransportChanges.Count) -gt 0) { @{ ids = @('DisableTransportRules'); tag = 'High'; text = "Review and disable $($flaggedTransportRules.Count + $flaggedTransportChanges.Count) tenant transport rule(s) changed in the window - these affect every mailbox." } }
        if ($stats.recentMfaDevices -gt 0) { @{ ids = @('RemoveMFA'); tag = 'Medium'; text = "Remove $($stats.recentMfaDevices) MFA method(s) registered during the window, then re-register trusted ones." } }
        if ($recentRegisteredDevices.Count -gt 0) { @{ ids = @('DisableRegisteredDevices|RemoveRegisteredDevices'); tag = 'Medium'; text = "Disable $($recentRegisteredDevices.Count) device(s) registered during the window so they cannot satisfy device-based Conditional Access." } }
        if ($stats.safelistChanges -gt 0) { @{ tag = 'Medium'; text = "Review $($stats.safelistChanges) trusted-sender / safelist change(s) that would let an attacker's future mail skip filtering." } }
        if ($flaggedAddIns.Count -gt 0) { @{ ids = @('DisableMailboxAddIns'); tag = 'Medium'; text = "Disable $($flaggedAddIns.Count) flagged mailbox add-in(s)." } }
    )
    $priorityActions = if ($tailoredActions.Count -gt 0) { $tailoredActions } else {
        @(@{ tag = 'Monitor'; text = 'No specific indicators require remediation. Continue monitoring the account for 30 days and keep MFA enforced as a precaution.' })
    }
    # Containment already run, by action id: when it last completed. The latest run that included an
    # action decides - completed only when none of its results in that run was an error.
    $completedAt = @{}
    foreach ($entry in @($bec.Run.Containment | Where-Object { $_ } | Sort-Object -Property { ToDate $_.At })) {
        foreach ($group in @($entry.Results | Where-Object { $_ -and $_.Action } | Group-Object -Property { "$($_.Action)" })) {
            $failed = @($group.Group | Where-Object { "$($_.state)" -eq 'error' }).Count -gt 0
            $completedAt[$group.Name] = if ($failed) { $null } else { ToDate $entry.At }
        }
    }
    # when every id an action needs ('A|B' = either) has completed, the latest of those times
    function CompletedAt([string[]]$Ids) {
        if (-not $Ids) { return $null }
        $times = foreach ($id in $Ids) {
            $at = @($id -split '\|' | ForEach-Object { $completedAt[$_] } | Where-Object { $_ } | Sort-Object -Descending)[0]
            if (-not $at) { return $null }
            $at
        }
        @($times | Sort-Object -Descending)[0]
    }
    $priorityRows = @($priorityActions | ForEach-Object {
            $tone = switch ($_.tag) { 'Critical' { 'fail' } 'High' { 'fail' } 'Medium' { 'warn' } default { 'pass' } }
            # The C-suite summary says which actions are already done instead of listing every result;
            # the full report keeps the action list as is and the detailed Remediation Taken table.
            $done = if ($isSummary) { CompletedAt $_.ids } else { $null }
            @{ tag = $_.tag; text = $(if ($done) { "$($_.text)`nCompleted $(FmtDate $done)" } else { $_.text }); tone = $tone }
        })

    # -- impact findings (the plain-terms outcome; mirrors impactFindings) --
    $impactFindings = @(
        if ($stats.foreignSuccessfulSignIns -gt 0 -or $foreignNonInteractive.Count -gt 0) { "Unauthorized access is confirmed - $($stats.foreignSuccessfulSignIns + $foreignNonInteractive.Count) successful sign-in(s) came from outside the account's assigned location." }
        if ($attackerIps.Count -gt 0) { "$(Plural $attackerIps.Count 'network address' 'network addresses')$(if ($attackerCountries.Count) { " in $(ListNames $attackerCountries)" }) $(if ($attackerIps.Count -eq 1) { 'was' } else { 'were' }) identified as the attacker's$(if ($attackerDid.Count) { "; from there the attacker $(ListNames $attackerDid 5)" })." }
        if ($attackerReach.Count -gt 0) { "The attack reached beyond this account: $(ListNames $attackerReach 3)." }
        if ($riskState.Listed) { "Microsoft Identity Protection currently flags this account as at risk$(if ($riskState.RiskLevel) { " ($($riskState.RiskLevel) risk)" })." }
        if ($hasForwarding) { "Incoming mail is being copied out of the organization$(if ($forwardingAddress) { " to $forwardingAddress" }), so the attacker keeps reading it even after a reset." }
        if ($stats.newRules -gt 0 -or $stats.ruleChanges -gt 0) { "$($stats.newRules + $stats.ruleChanges) inbox rule(s) or change(s) hide, delete or redirect the user's mail." }
        if ($stats.anonymousLinks -gt 0) { "$($stats.anonymousLinks) `"anyone with the link`" sharing link(s) expose files to anyone holding the URL, past any later reset." }
        if ($stats.massMailFlagged) { "The mailbox sent a mass-mail wave - $($stats.sentTotalMessages) message(s) to $($stats.sentTotalRecipients) recipient(s) - so it is now being used to attack others." }
        if ($flaggedGrants.Count -gt 0 -or $stats.maliciousApps -gt 0) { "$($flaggedGrants.Count + $stats.maliciousApps) risky application consent(s) or app(s) retain access to data independently of the password." }
        if ($stats.recentMfaDevices -gt 0 -or $recentRegisteredDevices.Count -gt 0) { "New sign-in persistence was added - $($stats.recentMfaDevices) MFA method(s) and $($recentRegisteredDevices.Count) device(s) registered during the window." }
        if ($flaggedDelegations.Count -gt 0) { "$($flaggedDelegations.Count) mailbox delegation(s) let another account read this mailbox." }
    )

    # ============================================================================================
    # Order of events - the correlated timeline (mirrors buildBecTimeline), collapsed per minute.
    # ============================================================================================
    $partnerKinds = @('Partner', 'OtherPartner', 'CIPP')
    $rawEvents = [System.Collections.Generic.List[object]]::new()
    # foreign sign-ins, and sign-ins from an address judged the attacker's even when it is at home
    foreach ($s in @($bec.SuspectUserSignIns | Where-Object { $_ -and ($_.ForeignLocation -eq $true -or (($SignInIp = HostIp (@($_.IPAddress, $_.ipAddress, $_.ClientIP) | Where-Object { $_ } | Select-Object -First 1)) -and $verdictByIp[$SignInIp] -in $attackerVerdicts)) })) {
        $rawEvents.Add(@{
                date     = ToDate (@($s.CreatedDateTime, $s.createdDateTime, $s.Timestamp) | Where-Object { $_ } | Select-Object -First 1)
                label    = "Sign-in $(if ($s.Status -eq 'Success') { 'success' } else { "($(if ($s.Status) { $s.Status } else { 'attempt' }))" })"
                ip       = HostIp (@($s.IPAddress, $s.ClientIP) | Where-Object { $_ } | Select-Object -First 1)
                app      = CleanStr (@($s.AppDisplayName, $s.ClientAppUsed) | Where-Object { $_ } | Select-Object -First 1)
                location = CleanStr ((@($s.City, $s.Country) | Where-Object { $_ }) -join ', ')
            })
    }
    foreach ($a in @($bec.DirectoryAudits | Where-Object { $_.Flagged })) {
        $rawEvents.Add(@{
                date    = ToDate $a.ActivityDateTime
                label   = if ($a.Activity) { "$($a.Activity)" } else { 'Directory change' }
                ip      = HostIp $a.ClientIP
                actor   = CleanStr (@($a.ActorResolved, $a.InitiatedBy) | Where-Object { $_ } | Select-Object -First 1)
                partner = ($partnerKinds -contains "$($a.ActorKind)")
            })
    }
    foreach ($c in @($bec.InboxRuleChanges)) {
        $rawEvents.Add(@{
                date    = ToDate $c.Date
                label   = if ($c.Operation) { "$($c.Operation)" } else { 'Inbox rule change' }
                ip      = HostIp $c.ClientIP
                target  = CleanStr $c.RuleName
                foreign = ($c.ForeignLocation -eq $true)
                partner = ($partnerKinds -contains "$($c.ActorKind)")
            })
    }
    foreach ($c in @($bec.MailboxPermissionChanges)) {
        $rawEvents.Add(@{
                date           = ToDate $c.Date
                label          = if ($c.Operation) { "$($c.Operation)" } else { 'Mailbox permission change' }
                ip             = HostIp $c.ClientIP
                targetsSuspect = [bool]$c.TargetsSuspect
                partner        = ($partnerKinds -contains "$($c.ActorKind)")
            })
    }
    foreach ($c in @($bec.SafelistChanges)) {
        $rawEvents.Add(@{
                date    = ToDate $c.Date
                label   = if ($c.Operation) { "$($c.Operation)" } else { 'Safelist change' }
                ip      = HostIp $c.ClientIP
                partner = ($partnerKinds -contains "$($c.ActorKind)")
            })
    }
    foreach ($c in @($bec.SharingChanges)) {
        $rawEvents.Add(@{
                date    = ToDate $c.Date
                label   = if ($c.Operation) { "$($c.Operation)" } else { 'Sharing change' }
                ip      = HostIp $c.ClientIP
                target  = CleanStr $c.FileName
                partner = ($partnerKinds -contains "$($c.ActorKind)")
            })
    }
    # Sent mail: one event each for a handful, else folded into one event per hour and source IP.
    $sentMsgs = @($bec.SentMessages)
    if ($sentMsgs.Count -le 25) {
        foreach ($m in $sentMsgs) {
            $rawEvents.Add(@{
                    date      = ToDate $m.Received
                    label     = 'Sent mail'
                    ip        = HostIp $m.FromIP
                    target    = CleanStr $m.Subject
                    recipient = CleanStr $m.RecipientAddress
                })
        }
    } else {
        $buckets = @{}
        foreach ($m in $sentMsgs) {
            $d = ToDate $m.Received
            if (-not $d) { continue }
            $hour = $d.Date.AddHours($d.Hour)
            $ip = HostIp $m.FromIP
            $key = '{0:o}|{1}' -f $hour, $ip
            if (-not $buckets.ContainsKey($key)) { $buckets[$key] = @{ date = $hour; ip = $ip; rows = [System.Collections.Generic.List[object]]::new() } }
            $buckets[$key].rows.Add($m)
        }
        foreach ($bucket in $buckets.Values) {
            $rows = @($bucket.rows)
            $emails = (@($rows | ForEach-Object { $_.MessageTraceId } | Where-Object { $_ } | Select-Object -Unique)).Count
            if ($emails -eq 0) { $emails = $rows.Count }
            $recipients = (@($rows | ForEach-Object { CleanStr $_.RecipientAddress } | Where-Object { $_ } | Select-Object -Unique)).Count
            $subjectGroups = $rows | Group-Object -Property { $s = CleanStr $_.Subject; if ($s) { $s } else { '(no subject)' } } | Sort-Object -Property Count -Descending
            $topSubject = ($subjectGroups | Select-Object -First 1).Name
            $rawEvents.Add(@{
                    date  = $bucket.date
                    label = "$emails email$(if ($emails -eq 1) { '' } else { 's' }) sent"
                    ip    = $bucket.ip
                    target = JoinDetail @("to $recipients recipient$(if ($recipients -eq 1) { '' } else { 's' })", $(if ($topSubject) { "`"$topSubject`"" }))
                })
        }
    }
    foreach ($f in @($bec.ReceivedMailFindings)) {
        $rawEvents.Add(@{
                date   = ToDate $f.Received
                label  = "Received: $(if ($f.FindingType) { $f.FindingType } else { 'finding' })"
                target = CleanStr $f.Subject
                sender = CleanStr $f.SenderAddress
            })
    }
    foreach ($t in @($bec.DefenderDetections | Where-Object { $_.Delivered })) {
        $rawEvents.Add(@{
                date   = ToDate $t.ReceivedDateTime
                label  = 'Threat delivered'
                target = CleanStr $t.Subject
                sender = CleanStr $t.SenderAddress
            })
    }
    foreach ($u in @($bec.NewUsers)) {
        $rawEvents.Add(@{ date = ToDate $u.createdDateTime; label = 'User created'; target = CleanStr $u.displayName })
    }
    foreach ($m in @($bec.MFADevices | Where-Object { $d = ToDate $_.createdDateTime; $d -and $d -ge $windowStart })) {
        $rawEvents.Add(@{ date = ToDate $m.createdDateTime; label = 'MFA method registered'; target = ("$($m.'@odata.type')" -replace '#microsoft\.graph\.', '') })
    }
    foreach ($dev in @($bec.RegisteredDevices | Where-Object { $_.RegisteredInWindow })) {
        $rawEvents.Add(@{ date = ToDate (@($dev.registrationDateTime, $dev.createdDateTime) | Where-Object { $_ } | Select-Object -First 1); label = 'Device registered'; target = CleanStr (@($dev.displayName, $dev.deviceId) | Where-Object { $_ } | Select-Object -First 1) })
    }
    foreach ($dev in @($bec.IntuneDevices | Where-Object { $d = ToDate $_.enrolledDateTime; $d -and $d -ge $windowStart })) {
        $rawEvents.Add(@{ date = ToDate $dev.enrolledDateTime; label = 'Intune device enrolled'; target = CleanStr (@($dev.deviceName, $dev.model) | Where-Object { $_ } | Select-Object -First 1) })
    }
    foreach ($u in @($bec.ChangedPasswords)) {
        $rawEvents.Add(@{ date = ToDate $u.lastPasswordChangeDateTime; label = 'Password changed'; target = CleanStr (@($u.displayName, $u.userPrincipalName) | Where-Object { $_ } | Select-Object -First 1) })
    }

    # What the attacker-side addresses did, folded to one event per hour, address and kind of action -
    # a mailbox sync or a scripted download is hundreds of rows that would bury everything else.
    $mailVerb = @{
        MailItemsAccessed = 'message(s) opened'; AttachmentAccess = 'attachment(s) read'; SoftDelete = 'item(s) deleted'
        HardDelete = 'item(s) purged'; MoveToDeletedItems = 'item(s) deleted'; Move = 'item(s) moved'; Send = 'message(s) sent'
        SendAs = 'message(s) sent as another mailbox'; SendOnBehalf = 'message(s) sent on behalf'; SearchQueryInitiatedExchange = 'mailbox search(es)'
    }
    $fileVerb = @{
        FileDownloaded = 'file(s) downloaded'; FileSyncDownloadedFull = 'file(s) synced down'; FileAccessed = 'file(s) opened'
        FilePreviewed = 'file(s) previewed'; FileUploaded = 'file(s) uploaded'; FileDeleted = 'file(s) deleted'; FileRecycled = 'file(s) deleted'
        SearchQueryPerformed = 'SharePoint search(es)'
    }
    function TopOf($Rows, [string]$Field) {
        (@($Rows | ForEach-Object { CleanStr $_.$Field } | Where-Object { $_ }) | Group-Object | Sort-Object -Property Count -Descending -Stable | Select-Object -First 1).Name
    }
    function FoldActivity($Rows, [scriptblock]$KeyOf) {
        $buckets = [ordered]@{}
        foreach ($row in @($Rows | Where-Object { $_ })) {
            $d = ToDate $row.When
            if (-not $d) { continue }
            $u = $d.ToUniversalTime()
            $ip = HostIp $row.IP
            $key = '{0:yyyyMMddHH}|{1}|{2}' -f $u, $ip, (& $KeyOf $row)
            if (-not $buckets.Contains($key)) { $buckets[$key] = @{ date = $d; ip = $ip; rows = [System.Collections.Generic.List[object]]::new() } }
            $buckets[$key].rows.Add($row)
        }
        @($buckets.Values)
    }
    foreach ($bucket in (FoldActivity $bec.AttackerMailActivity { param($row) "$($row.Operation)|$(if ($row.AccessType -eq 'Sync') { 'sync' })" })) {
        $first = $bucket.rows[0]
        $n = $bucket.rows.Count
        if ($first.AccessType -eq 'Sync') {
            $rawEvents.Add(@{ date = $bucket.date; ip = $bucket.ip; label = "$n folder(s) synced to a desktop client"; target = (TopOf $bucket.rows 'Folder') })
        } else {
            $verb = if ($mailVerb[[string]$first.Operation]) { $mailVerb[[string]$first.Operation] } else { "$($first.Operation) event(s)" }
            $target = TopOf $bucket.rows 'Subject'
            if (-not $target) { $target = TopOf $bucket.rows 'Folder' }
            $rawEvents.Add(@{ date = $bucket.date; ip = $bucket.ip; label = "$n $verb"; target = $target })
        }
    }
    foreach ($bucket in (FoldActivity $bec.AttackerFileActivity { param($row) "$($row.Operation)" })) {
        $first = $bucket.rows[0]
        $verb = if ($fileVerb[[string]$first.Operation]) { $fileVerb[[string]$first.Operation] } else { "$($first.Operation) event(s)" }
        $rawEvents.Add(@{ date = $bucket.date; ip = $bucket.ip; label = "$($bucket.rows.Count) $verb"; target = (TopOf $bucket.rows 'File') })
    }
    foreach ($f in @($bec.FormsActivity | Where-Object { $_.Flagged -eq $true })) {
        $rawEvents.Add(@{ date = ToDate $f.When; ip = HostIp $f.IP; label = "Form: $($f.Operation)"; target = CleanStr $f.FormName })
    }

    $sortedEvents = @($rawEvents | Where-Object { $_.date } | Sort-Object -Property date)
    $timelineEvents = [System.Collections.Generic.List[object]]::new()
    $prev = $null
    foreach ($e in $sortedEvents) {
        $detail = JoinDetail @(
            $e.location, $e.app, $e.actor, $e.target,
            $(if ($e.recipient) { "to $($e.recipient)" }),
            $e.sender,
            $(if ($e.foreign) { 'foreign' }),
            $(if ($e.partner) { 'partner action' }),
            $(if ($e.targetsSuspect) { 'targets this mailbox' }),
            $e.ip
        )
        $minute = $e.date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm')
        if ($prev -and $prev.minute -eq $minute -and $prev.label -eq $e.label -and $prev.detail -eq $detail) {
            $prev.count++
            continue
        }
        $prev = @{ minute = $minute; label = $e.label; detail = $detail; date = $e.date; count = 1 }
        $timelineEvents.Add($prev)
    }
    $timelineRows = @($timelineEvents | ForEach-Object {
            @{ when = (FmtDate $_.date); event = $(if ($_.count -gt 1) { "$($_.label) (x$($_.count))" } else { $_.label }); detail = $_.detail }
        })

    # -- remediation already run (from the run's stored containment history) --
    $remediationRows = @(@($bec.Run.Containment) | Where-Object { $_ } | Sort-Object -Property { ToDate $_.At } -Descending | ForEach-Object {
            $entry = $_
            foreach ($row in @($entry.Results)) {
                $state = "$($row.state)"
                $tone = switch ($state) { 'success' { 'pass' } 'error' { 'fail' } 'warning' { 'warn' } default { '' } }
                @{
                    when   = (FmtDate $entry.At)
                    action = (("$($row.Action)" -replace '([a-z0-9])([A-Z])', '$1 $2').Trim())
                    target = "$($row.Target)"
                    result = "$($row.resultText)"
                    state  = $state
                    tone   = $tone
                }
            }
        })

    $b = [System.Collections.Generic.List[object]]::new()

    # === PAGE 1: EXECUTIVE SUMMARY ===
    $b.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'Overview of Business Email Compromise investigation findings'))
    $b.Add((New-CippReportParagraph -Html ('<p>This report documents the findings of a Business Email Compromise (BEC) investigation performed for the user account <b>{0}</b> within <b>{1}</b>. The investigation analyzed suspicious activity indicators including mailbox rules, permission changes, new applications, authentication patterns, and sign-in locations over a {2}-day period.</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$upn), [System.Net.WebUtility]::HtmlEncode([string]$TenantName), $windowDays)))
    $b.Add((New-CippReportParagraph -Text 'Business Email Compromise is a sophisticated scam targeting organizations that regularly perform wire transfers or have established relationships with foreign suppliers. Attackers compromise legitimate email accounts through social engineering or computer intrusion techniques to conduct unauthorized fund transfers, steal sensitive information, or impersonate executives.'))

    $b.Add((New-CippReportHeading -Title 'Investigation Overview'))
    $b.Add((New-CippReportStatRow -Stats @(
                @{ value = $stats.newRules; label = 'Mailbox Rules' }
                @{ value = $stats.permissionChanges; label = 'Permission Changes' }
                @{ value = $stats.foreignSignIns; label = 'Foreign Sign-ins' }
                @{ value = $stats.maliciousApps; label = 'Malicious Apps' }
            )))
    $threatText = switch ($threatLevel) {
        'High' { 'HIGH RISK: Multiple indicators of compromise detected. Immediate remediation actions are strongly recommended. This account shows patterns consistent with active Business Email Compromise attacks.' }
        'Medium' { 'MEDIUM RISK: Suspicious activity patterns detected. Review findings and consider implementing recommended security measures. Some indicators suggest potential unauthorized access.' }
        default { 'LOW RISK: Minimal suspicious activity detected. The findings show standard user behavior with no significant indicators of compromise. Continue monitoring as a precautionary measure.' }
    }
    $b.Add((New-CippReportAlertBox -Colour $threatColour -Title "Threat Assessment: $threatLevel (score $threatValue)" -Content $threatText))
    if ($appliedSignals.Count -gt 0) {
        $b.Add((New-CippReportInfoBox -Lines -Title 'Signals that contributed to the score' -Content ((@($appliedSignals | ForEach-Object { "+$(AsInt $_.Weight) $($_.Description) ($(AsInt $_.Count))" })) -join "`n")))
    }

    $b.Add((New-CippReportHeading -Title 'What We Found'))
    if ($impactFindings.Count -gt 0) {
        $b.Add((New-CippReportParagraph -Html ('<p>In plain terms, this is what the investigation established about <b>{0}</b>:</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$upn))))
        $b.Add((New-CippReportBullets -Items @($impactFindings | ForEach-Object { @{ text = $_ } })))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No indicators of account compromise' -Content "None of the investigation's checks returned evidence that this account was accessed, altered or misused during the analysis window."))
    }

    $b.Add((New-CippReportHeading -Title 'Findings at a Glance'))
    $b.Add((New-CippReportParagraph -Text ("Every check in this investigation and its result. $(if (-not $isSummary) { 'Flagged rows are expanded in the detailed findings later in this report. ' })$flaggedAreaCount of $($summaryData.Count) checks returned something to review.")))
    if ($totalFindings -gt 0) {
        $b.Add((New-CippReportParagraph -Html '<p><b>Findings by attacker objective</b> - grouped by what each finding would let an attacker do:</p>'))
        $b.Add((New-CippReportProgress -Items @($objectiveData | ForEach-Object { @{ label = $_.label; value = $_.value; max = $objectiveMax; display = "$($_.value)"; colour = $_.colour } })))
    }
    $b.Add((New-CippReportTable -Columns @(
                @{ header = 'Check'; key = 'area'; width = 3; bold = $true }
                @{ header = 'Result'; key = 'result'; width = 2; toneField = 'tone' }
            ) -Rows @($summaryData) -Limit $summaryData.Count))
    if (-not $isSummary) {
        $b.Add((New-CippReportNote -Text 'Checks that could not run (missing a licence, permission, mailbox or service) are itemised under Data Source Information below - a check that did not run is not a pass.'))
    }

    $b.Add((New-CippReportHeading -Title 'Priority Remediation Actions'))
    $b.Add((New-CippReportParagraph -Text ("Actions specific to what this investigation found, most urgent first. Your IT or security team should carry these out without delay$(if (-not $isSummary) { '; the strategic and preventative measures follow later in this report.' } else { '.' })")))
    $b.Add((New-CippReportTable -Columns @(
                @{ header = 'Priority'; key = 'tag'; width = 1; toneField = 'tone' }
                @{ header = 'Action'; key = 'text'; width = 5 }
            ) -Rows @($priorityRows) -Limit $priorityRows.Count))

    $b.Add((New-CippReportHeading -Title 'Order of Events'))
    if ($timelineRows.Count -gt 0) {
        $b.Add((New-CippReportParagraph -Text 'Every timestamped signal - sign-ins, directory and mailbox changes, sharing, and the mail itself - in the order it happened, with who and where where known. Read it as the shape of the intrusion over time, not as isolated findings.'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Event'; key = 'event'; width = 2 }
                    @{ header = 'Detail'; key = 'detail'; width = 3 }
                ) -Rows @($timelineRows) -Limit 40))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No timestamped events in the window' -Content 'None of the checks returned a dated event inside the analysis window. This usually means no changes were made to the account in the period, not that data was missing.'))
    }

    if ($remediationRows.Count -gt 0 -and -not $isSummary) {
        $b.Add((New-CippReportHeading -Title 'Remediation Taken'))
        $b.Add((New-CippReportParagraph -Text 'The containment actions already run for this account during the investigation, and their result for each target.'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Action'; key = 'action'; width = 2 }
                    @{ header = 'Target'; key = 'target'; width = 2 }
                    @{ header = 'Result'; key = 'result'; width = 3 }
                    @{ header = 'State'; key = 'state'; width = 1; toneField = 'tone' }
                ) -Rows @($remediationRows) -Limit $remediationRows.Count))
    }

    # Data Source Information and every detail page (Understanding BEC, Checks 1-21, Recommendations,
    # Compliance) are the full report only; the summary variant stops after the executive lead.
    if (-not $isSummary) {
    $b.Add((New-CippReportHeading -Title 'Data Source Information'))
    $b.Add((New-CippReportInfoBox -Title 'Audit Log Status' -Content $(if ($bec.ExtractResult) { "$($bec.ExtractResult)" } else { 'Unknown' })))
    $b.Add((New-CippReportInfoBox -Title 'Analysis Period' -Content ("Last $windowDays days ending {0}" -f (FmtDate $bec.ExtractedAt))))
    if ($bec.Run.CaseId -or $bec.CaseId) {
        $caseId = if ($bec.Run.CaseId) { $bec.Run.CaseId } else { $bec.CaseId }
        $b.Add((New-CippReportInfoBox -Title 'Case' -Content "$caseId - full investigation. Metadata only: audit records, sign-ins, trace headers, permissions, rules and devices were collected; no message content was read."))
    }
    if ($skippedCollectors.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($skippedCollectors.Count) check(s) could not run (not applicable to this tenant or user)" -Content ((@($skippedCollectors | ForEach-Object { "$($_.Name): $(if ($_.Value.Requirement) { $_.Value.Requirement } elseif ($_.Value.Error) { $_.Value.Error } else { 'not checked' })" })) -join "`n")))
    }
    if ($incompleteCollectors.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($incompleteCollectors.Count) check(s) returned partial data" -Content ((@($incompleteCollectors | ForEach-Object { "$($_.Name): $(if ($_.Value.Error) { $_.Value.Error } else { "capped at $($_.Value.Cap)" })" })) -join "`n")))
    }
    $b.Add((New-CippReportInfoBox -Title 'Assigned Usage Location' -Content $(if ($usageLoc) { "$usageLoc" } else { 'Not assigned - sign-ins and activity could not be compared against an expected country' })))

    # === ATTACKER ADDRESSES & ACTIVITY - capped lists; the evidence export has every row ===
    if ($ipVerdicts.Count -gt 0) {
        $b.Add((New-CippReportPage -Title 'Attacker Addresses & Activity' -Subtitle 'Where the attacker connected from, and what was done from there'))
        $b.Add((New-CippReportHeading -Title 'Attacker and Suspicious Addresses'))
        $b.Add((New-CippReportParagraph -Text "Every address seen on this account was judged from the user's sign-in history, network and location, the IP allow and block lists, and the other accounts using it. Addresses judged the attacker's drive the findings below; suspicious ones are listed for review only."))
        if ($reviewIps.Count -gt 0) {
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'Address'; key = 'ip'; width = 2; bold = $true }
                        @{ header = 'Verdict'; key = 'verdict'; width = 2; toneField = 'tone' }
                        @{ header = 'Location'; key = 'location'; width = 2 }
                        @{ header = 'Sign-ins'; key = 'signIns'; width = 1 }
                        @{ header = 'Why'; key = 'why'; width = 4 }
                    ) -Rows @($reviewIps | ForEach-Object {
                        $place = (@($_.City, $_.Country) | Where-Object { $_ }) -join ', '
                        @{
                            ip       = "$($_.IP)"
                            verdict  = ("$($_.Verdict)" -creplace '([a-z])([A-Z])', '$1 $2')
                            tone     = $(if ($_.Verdict -in $attackerVerdicts) { 'fail' } else { 'warn' })
                            location = $(if ($place) { $place } else { 'Unknown' })
                            signIns  = "$(AsInt $_.SuccessfulSignIns) ok / $(AsInt $_.FailedSignIns) failed"
                            why      = (VerdictWhy $_)
                        }
                    }) -Limit 15))
        } else {
            $b.Add((New-CippReportClearBox -Title "[Pass] No address was judged the attacker's" -Content "None of the $($ipVerdicts.Count) address(es) seen on this account was judged to be the attacker's or suspicious."))
        }

        if (($attackerMail.Count + $attackerFiles.Count) -gt 0) {
            $b.Add((New-CippReportHeading -Title "What Was Done From the Attacker's Addresses"))
            $b.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($attackerTotals.opened)"; label = 'Emails Opened' }
                        @{ value = "$($attackerTotals.sent)"; label = 'Emails Sent' }
                        @{ value = "$($attackerTotals.deleted)"; label = 'Emails Deleted' }
                        @{ value = "$($attackerTotals.files)"; label = 'Files Opened' }
                    )))
            if ($attackerMail.Count -gt 0) {
                $b.Add((New-CippReportTable -Columns @(
                            @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                            @{ header = 'Action'; key = 'action'; width = 2 }
                            @{ header = 'Mailbox'; key = 'mailbox'; width = 2 }
                            @{ header = 'Item'; key = 'item'; width = 4 }
                        ) -Rows @($attackerMail | ForEach-Object {
                            @{
                                when    = (FmtDate $_.When)
                                action  = $(if ($_.AccessType) { "$($_.Operation) ($($_.AccessType))" } else { "$($_.Operation)" })
                                mailbox = $(if (-not $_.MailboxOwner -or "$($_.MailboxOwner)" -ieq "$upn") { 'This mailbox' } else { "$($_.MailboxOwner)" })
                                item    = "$(@($_.Subject, $_.Folder, $_.Detail) | Where-Object { $_ } | Select-Object -First 1)"
                            }
                        }) -Limit 10))
            }
            if ($attackerFiles.Count -gt 0) {
                $b.Add((New-CippReportTable -Columns @(
                            @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                            @{ header = 'Action'; key = 'action'; width = 2 }
                            @{ header = 'File'; key = 'file'; width = 3 }
                            @{ header = 'Site'; key = 'site'; width = 3 }
                        ) -Rows @($attackerFiles | ForEach-Object {
                            @{ when = (FmtDate $_.When); action = "$($_.Operation)"; file = $(if ($_.File) { "$($_.File)" } else { "$($_.Url)" }); site = "$($_.Site)" }
                        }) -Limit 10))
            }
            $b.Add((New-CippReportNote -Text "The first items of each kind are shown; the complete item list is in the case's evidence export."))
        }

        if ($blastRadius.Count -gt 0) {
            $b.Add((New-CippReportHeading -Title 'Other Accounts Reached'))
            $b.Add((New-CippReportParagraph -Text "Accounts elsewhere in the organization that signed in or acted from the attacker's addresses. A successful sign-in or any recorded action means the account was reached; failed sign-ins alone are an attempt."))
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'Account'; key = 'account'; width = 3; bold = $true }
                        @{ header = 'Status'; key = 'status'; width = 1; toneField = 'tone' }
                        @{ header = 'Sign-ins'; key = 'signIns'; width = 2 }
                        @{ header = 'Actions'; key = 'operations'; width = 3 }
                        @{ header = 'Last seen'; key = 'lastSeen'; width = 2 }
                    ) -Rows @($blastRadius | ForEach-Object {
                        @{
                            account    = "$($_.UserPrincipalName)"
                            status     = $(if ($_.Reached -eq $true) { 'Reached' } else { 'Attempted' })
                            tone       = $(if ($_.Reached -eq $true) { 'fail' } else { 'warn' })
                            signIns    = "$(AsInt $_.SuccessfulSignIns) ok / $(AsInt $_.FailedSignIns) failed"
                            operations = $(if ($_.Operations) { "$($_.Operations)" } else { '-' })
                            lastSeen   = (FmtDate $_.LastSeen)
                        }
                    }) -Limit 15))
        }

        if ($delegatedReached.Count -gt 0) {
            $b.Add((New-CippReportHeading -Title 'Other Mailboxes Reached Through This Account'))
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'Mailbox'; key = 'mailbox'; width = 3; bold = $true }
                        @{ header = 'Access'; key = 'access'; width = 3 }
                        @{ header = 'Opened'; key = 'opened'; width = 1 }
                        @{ header = 'Synced'; key = 'synced'; width = 1 }
                        @{ header = 'Sent'; key = 'sent'; width = 1 }
                    ) -Rows @($delegatedReached | ForEach-Object {
                        @{ mailbox = "$($_.Mailbox)"; access = "$($_.AccessRights)"; opened = "$(AsInt $_.AttackerOpened)"; synced = "$(AsInt $_.AttackerSynced)"; sent = "$(AsInt $_.AttackerSent)" }
                    }) -Limit 10))
        }

        if ($attackerFormIds.Count -gt 0) {
            $b.Add((New-CippReportHeading -Title "Microsoft Forms From the Attacker's Addresses"))
            $b.Add((New-CippReportParagraph -Text "Forms built or shared from the attacker's addresses, and how far they reached. A form asking for a password is a phishing page hosted on Microsoft's own domain. No API removes a single form: confirm phishing and delete it from its Microsoft Defender alert, or, after the password reset, delete it in Microsoft Forms as the account."))
            $formRows = if ($formsReach.Count -gt 0) {
                @($formsReach | ForEach-Object {
                        @{ name = $(if ($_.FormName) { "$($_.FormName)" } else { "$($_.FormId)" }); responses = "$(AsInt $_.Responses)"; anonymous = "$(AsInt $_.AnonymousResponses)"; views = "$(AsInt $_.Views)"; flagged = $(if ($_.PhishingFlagged -eq $true) { 'Yes' } else { 'No' }) }
                    })
            } else {
                @($attackerFormNames | ForEach-Object { @{ name = "$_"; responses = '-'; anonymous = '-'; views = '-'; flagged = '-' } })
            }
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'Form'; key = 'name'; width = 4; bold = $true }
                        @{ header = 'Responses'; key = 'responses'; width = 1 }
                        @{ header = 'Anonymous'; key = 'anonymous'; width = 1 }
                        @{ header = 'Views'; key = 'views'; width = 1 }
                        @{ header = 'Phishing flag'; key = 'flagged'; width = 2 }
                    ) -Rows @($formRows) -Limit 10))
        }
    }

    # === PAGE 2: UNDERSTANDING BEC ===
    $b.Add((New-CippReportPage -Title 'Understanding Business Email Compromise' -Subtitle 'What is BEC and why does it matter?'))
    $b.Add((New-CippReportParagraph -Title 'What is Business Email Compromise?' -Text 'Business Email Compromise (BEC) is a type of cyberattack where criminals gain unauthorized access to a business email account. Once inside, attackers can:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'Monitor communications:'; text = 'Read sensitive emails to learn about business operations, financial processes, and key relationships.' }
                @{ label = 'Impersonate executives:'; text = 'Send fraudulent emails appearing to come from company leadership requesting wire transfers or sensitive data.' }
                @{ label = 'Manipulate transactions:'; text = 'Intercept legitimate invoices and alter payment information to redirect funds to attacker-controlled accounts.' }
                @{ label = 'Hide their tracks:'; text = 'Create email rules to automatically delete or hide messages, preventing detection.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Common Attack Methods' -Text 'Attackers typically gain access to email accounts through:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'Phishing:'; text = 'Deceptive emails that trick users into providing their login credentials on fake websites.' }
                @{ label = 'Password Spraying:'; text = 'Automated attempts to log in using common passwords across many accounts.' }
                @{ label = 'Credential Stuffing:'; text = 'Using usernames and passwords leaked from other breached websites.' }
                @{ label = 'Malware:'; text = 'Software that captures keystrokes or steals stored passwords from compromised devices.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Why This Investigation Was Performed' -Text 'This analysis was initiated because suspicious activity was detected or reported for this user account. The investigation examines multiple indicators that might suggest account compromise, including unusual mailbox rules, unexpected permission changes, new application authorizations, and abnormal sign-in patterns. Early detection is critical to minimize potential damage and prevent financial loss or data theft.'))

    # === PAGE 3: DETAILED FINDINGS - Check 1 ===
    $b.Add((New-CippReportPage -Title 'Detailed Findings' -Subtitle 'Investigation results and analysis'))
    $b.Add((New-CippReportHeading -Title 'Check 1: Mailbox Rules'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers often create email rules to automatically forward, delete, or hide messages so victims never see evidence of fraudulent activity. A rule is flagged when it forwards or redirects mail (especially to an external address), deletes messages, moves them to a low-visibility folder (RSS, Archive, Deleted Items), stops processing other rules, targets financial keywords, or takes any of these actions on all incoming mail with no condition.'))
    if ($stats.newRules -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.newRules) Mailbox Rule(s) Found" -Content 'The following mailbox rules were detected. Review each rule carefully to determine if it was created by the user or by an attacker. Rules that forward emails or move them to unusual folders are particularly suspicious.'))
        foreach ($rule in @($bec.NewRules | Select-Object -First 10)) {
            $lines = @(
                if ($rule.MoveToFolder) { "Moves mail to: $($rule.MoveToFolder)" }
                if ($rule.ForwardTo) { "Forwards to: $($rule.ForwardTo)" }
                if ($rule.ForwardAsAttachmentTo) { "Forwards as attachment to: $($rule.ForwardAsAttachmentTo)" }
                if ($rule.RedirectTo) { "Redirects to: $($rule.RedirectTo)" }
                if ($rule.DeleteMessage) { 'Deletes messages' }
                if ($rule.MarkAsRead) { 'Marks messages read' }
                if ($rule.StopProcessingRules) { 'Stops processing further rules' }
                if ($rule.SubjectContainsWords) { "On subject words: $(if ($rule.SubjectContainsWords -is [array]) { $rule.SubjectContainsWords -join ', ' } else { $rule.SubjectContainsWords })" }
                if ($rule.RecentlyChanged) { 'Created or changed in the window' }
                if ($rule.Enabled -eq $false) { 'Currently disabled' }
            )
            $content = if ($lines.Count -gt 0) { $lines -join "`n" } elseif ($rule.Description) { "$($rule.Description)" } else { 'No actions recorded on this rule' }
            $b.Add((New-CippReportInfoBox -Lines -Title "Rule: $(if ($rule.Name) { $rule.Name } else { 'Unnamed Rule' })" -Content $content))
        }
        if ($stats.newRules -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.newRules - 10) more rules (in the retained investigation record)")) }
    }
    if ($stats.ruleChanges -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.ruleChanges) Rule Change(s) in the Last $windowDays Days" -Content 'The audit log recorded inbox rules being created, changed or removed on this mailbox. Rules that were removed after use are a common way for attackers to cover their tracks.'))
        foreach ($change in @($bec.InboxRuleChanges | Select-Object -First 10)) {
            $lines = @(
                "Date: $(if ($change.Date) { $change.Date } else { 'Unknown' })"
                "By: $(if ($change.UserKey) { $change.UserKey } else { 'Unknown' })"
                if ($change.ClientIP) { "From: $($change.ClientIP)$(if ($change.Country) { " ($($change.Country))" })" }
                if ($change.ForeignLocation -eq $true) { '[!] Originated outside the assigned usage location' }
                if ($change.Parameters) { "Parameters: $($change.Parameters)" }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Rule Change' }): $(if ($change.RuleName) { $change.RuleName } else { 'Unnamed Rule' })" -Content ($lines -join "`n")))
        }
        if ($stats.ruleChanges -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.ruleChanges - 10) more changes (see the retained investigation record for the full list)")) }
    }
    if ($stats.newRules -eq 0 -and $stats.ruleChanges -eq 0) {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Suspicious Rules Found' -Content 'No mailbox rules were detected that match suspicious patterns. This is a positive indicator.'))
    }

    # === PAGE 4: DETAILED FINDINGS (Continued) - Check 2, 3 ===
    $b.Add((New-CippReportPage -Title 'Detailed Findings (Continued)' -Subtitle 'Investigation results and analysis'))
    $b.Add((New-CippReportHeading -Title 'Check 2: Recently Created Users'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers sometimes create new user accounts to maintain persistent access or to use as staging accounts for fraudulent activities. Reviewing recently created users helps identify unauthorized account creation.'))
    if ($stats.newUsers -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[i] $($stats.newUsers) New User(s) Found" -Content "The following users were created in the last $windowDays days. Verify that each account creation was authorized and legitimate."))
        foreach ($u in @($bec.NewUsers | Select-Object -First 8)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($u.displayName) { $u.displayName } else { 'Unknown' })" -Content ("Email: $(if ($u.userPrincipalName) { $u.userPrincipalName } else { 'N/A' })`nCreated: $(FmtDate $u.createdDateTime)")))
        }
        if ($stats.newUsers -gt 8) { $b.Add((New-CippReportNote -Text "... and $($stats.newUsers - 8) more users (see the retained investigation record for the full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No New Users Found' -Content 'No new user accounts were created during the analysis period.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 3: New Applications'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content "Attackers may authorize malicious or suspicious third-party applications to access your email and data. These applications can read emails, send messages, and access files without the user's explicit knowledge."))
    if ($stats.maliciousApps -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.maliciousApps) Known-Malicious Application(s) Detected" -Content 'One or more applications in this tenant match the CIPP known-malicious application catalog. Consent-based access survives a password reset, so these applications should be removed unless their presence is explained.'))
    }
    if ($stats.newApps -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.newApps) New Application(s) Found" -Content 'New applications were granted access during the analysis period. Review each application to ensure it was authorized and is from a trusted publisher.'))
        foreach ($app in @($bec.AddedApps | Select-Object -First 6)) {
            $lines = @(
                "Publisher: $(if ($app.publisher) { $app.publisher } else { 'Unknown' })"
                "App ID: $(if ($app.appId) { $app.appId } else { 'N/A' })"
                "Created: $(FmtDate $app.createdDateTime)"
                if ($app.MaliciousMatch) {
                    $cats = if ($app.MaliciousMatch.Categories) { " ($($app.MaliciousMatch.Categories -join ', '))" } else { '' }
                    "[!] Matches known-malicious catalog entry `"$($app.MaliciousMatch.Name)`"$cats"
                }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($app.displayName) { $app.displayName } elseif ($app.appDisplayName) { $app.appDisplayName } else { 'Unknown' })" -Content ($lines -join "`n")))
        }
        if ($stats.newApps -gt 6) { $b.Add((New-CippReportNote -Text "... and $($stats.newApps - 6) more apps (see the retained investigation record for the full list)")) }
    } elseif ((Cnt $bec.MaliciousSPs) -eq 0) {
        $b.Add((New-CippReportClearBox -Title '[Pass] No New Applications Found' -Content 'No new applications were authorized during the analysis period, and no known malicious applications are present in the tenant.'))
    }
    if ((Cnt $bec.MaliciousSPs) -gt 0) {
        foreach ($app in @($bec.MaliciousSPs | Select-Object -First 6)) {
            $lines = @(
                "Catalog entry: $(if ($app.CatalogName) { $app.CatalogName } else { 'Unknown' })"
                "App ID: $(if ($app.appId) { $app.appId } else { 'N/A' })"
                "Categories: $(if ($app.Categories) { $app.Categories -join ', ' } else { 'N/A' })"
                "Enabled: $(if ($null -ne $app.accountEnabled) { $app.accountEnabled } else { 'Unknown' })"
                "First seen: $(FmtDate $app.createdDateTime)"
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "[!] $(if ($app.displayName) { $app.displayName } else { 'Unknown' }) (present in tenant)" -Content ($lines -join "`n")))
        }
        if ((Cnt $bec.MaliciousSPs) -gt 6) { $b.Add((New-CippReportNote -Text "... and $((Cnt $bec.MaliciousSPs) - 6) more (see the retained investigation record for the full list)")) }
    }

    # === PAGE 5: ADDITIONAL SECURITY CHECKS - Check 4,5,6,7 ===
    $b.Add((New-CippReportPage -Title 'Additional Security Checks' -Subtitle 'Permissions, outbound mail, authentication, and access patterns'))
    $b.Add((New-CippReportHeading -Title 'Check 4: Mailbox Permission Changes'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Unauthorized changes to mailbox permissions can allow attackers to grant themselves or accomplices access to read, send, or manage emails. This is a common technique to maintain persistent access.'))
    if ($stats.permissionChanges -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.permissionChanges) Permission Change(s) Found" -Content 'Mailbox permission changes were detected. Verify that each change was authorized and necessary for legitimate business purposes.'))
        foreach ($change in @($bec.MailboxPermissionChanges | Select-Object -First 5)) {
            $lines = @(
                "User: $(if ($change.UserKey) { $change.UserKey } else { 'Unknown' })"
                "Target: $(if ($change.ObjectId) { $change.ObjectId } else { 'N/A' })"
                "Permissions: $(if ($change.Permissions) { $change.Permissions } else { 'Unknown' })"
                if ($change.TargetsSuspect -eq $true) { '[!] Targets the investigated mailbox' }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Permission Change' })" -Content ($lines -join "`n")))
        }
        if ($stats.permissionChanges -gt 5) { $b.Add((New-CippReportNote -Text "... and $($stats.permissionChanges - 5) more changes")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Permission Changes Found' -Content 'No mailbox permission changes were detected during the analysis period.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 5: Sent Messages'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers use a compromised mailbox to send fraudulent invoices, phishing, or internal impersonation mail. The message trace shows what actually left the mailbox during the analysis period, including the IP address it was sent from.'))
    if ($stats.sentMessages -gt 0) {
        $totMsg = if ($stats.sentTotalMessages) { $stats.sentTotalMessages } else { $stats.sentMessages }
        $totRcp = if ($stats.sentTotalRecipients) { $stats.sentTotalRecipients } else { $stats.sentMessages }
        $foreignTail = if ($stats.foreignSentMessages -gt 0) { ", including $($stats.foreignSentMessages) from an IP outside the user's assigned usage location." } else { '.' }
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $totMsg message(s) to $totRcp recipient(s) were sent by this mailbox during the analysis period$foreignTail"))
        if ($stats.massMailFlagged) {
            $mm = -join @(
                if ($stats.repeatedSubjects -gt 0) { "$($stats.repeatedSubjects) subject(s) were sent as many separate messages or to many recipients. " }
                if ($stats.sendBursts -gt 0) { "$($stats.sendBursts) short burst(s) of high-volume sending were detected. " }
                'Identical-subject mass mail and send bursts are how a compromised mailbox spreads phishing or fraudulent invoices. Review the campaigns below and warn the recipients if the content was malicious.'
            )
            $b.Add((New-CippReportAlertBox -Title '[!] Mass-Mail Pattern Detected' -Content $mm))
        }
        foreach ($g in @($ana.RepeatedSubjects | Select-Object -First 5)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($g.Flagged) { '[!] ' })Repeated subject: $(if ($g.Subject) { $g.Subject } else { '(no subject)' })" -Content ("Messages: $($g.MessageCount)`nRecipients: $($g.RecipientCount)`nFirst sent: $(if ($g.FirstSent) { $g.FirstSent } else { 'N/A' })`nLast sent: $(if ($g.LastSent) { $g.LastSent } else { 'N/A' })")))
        }
        if ((Cnt $ana.RepeatedSubjects) -gt 5) { $b.Add((New-CippReportNote -Text "... and $((Cnt $ana.RepeatedSubjects) - 5) more repeated subjects (see the retained investigation record for the full list)")) }
        foreach ($burst in @($ana.Bursts | Select-Object -First 5)) {
            $win = if ($burst.WindowMinutes) { $burst.WindowMinutes } else { 10 }
            $content = @(
                "Starting: $(if ($burst.WindowStart) { $burst.WindowStart } else { 'N/A' })"
                if ($burst.TopSubject) { "Most common subject: $($burst.TopSubject)" }
            ) -join "`n"
            $b.Add((New-CippReportInfoBox -Lines -Title "[!] Send burst: $($burst.MessageCount) message(s) to $($burst.RecipientCount) recipient(s) in $win minutes" -Content $content))
        }
        if ((Cnt $ana.Bursts) -gt 5) { $b.Add((New-CippReportNote -Text "... and $((Cnt $ana.Bursts) - 5) more bursts (see the retained investigation record for the full list)")) }
        foreach ($msg in @($bec.SentMessages | Select-Object -First 10)) {
            $lines = @(
                "To: $(if ($msg.RecipientAddress) { $msg.RecipientAddress } else { 'N/A' })"
                "Status: $(if ($msg.Status) { $msg.Status } else { 'N/A' })"
                "Received: $(if ($msg.Received) { $msg.Received } else { 'N/A' })"
                if ($msg.FromIP) { "From IP: $($msg.FromIP)$(if ($msg.Country) { " ($($msg.Country))" })" }
                if ($msg.ForeignLocation -eq $true) { '[!] Sent from outside the assigned usage location' }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($msg.Subject) { $msg.Subject } else { '(no subject)' })" -Content ($lines -join "`n")))
        }
        if ($stats.sentMessages -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.sentMessages - 10) more messages (see the retained investigation record for the full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Sent Messages Found' -Content 'No messages were sent by this mailbox during the analysis period.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 6: MFA Devices'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Multi-factor authentication (MFA) devices provide an additional layer of security. Reviewing registered MFA methods helps identify if attackers have added unauthorized devices to bypass security controls.'))
    if ($stats.mfaDevices -gt 0) {
        $mfaTail = if ($stats.recentMfaDevices -gt 0) { ", including $($stats.recentMfaDevices) registered in the last $windowDays days. Verify the recent registrations were made by the user - attackers register their own method to keep access after a password reset." } else { '. Verify each device belongs to the user.' }
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($stats.mfaDevices) MFA device(s) registered$mfaTail"))
        $sortedMfa = @($bec.MFADevices | Sort-Object -Property @{ Expression = { $d = ToDate $_.createdDateTime; if ($d) { $d } else { [datetime]0 } }; Descending = $true } | Select-Object -First 5)
        foreach ($device in $sortedMfa) {
            $type = "$($device.'@odata.type')".Replace('#microsoft.graph.', '').Replace('AuthenticationMethod', '')
            $lines = @(
                "Display Name: $(if ($device.displayName) { $device.displayName } else { 'N/A' })"
                "Registered: $(FmtDate $device.createdDateTime)"
                $(if (($d = ToDate $device.createdDateTime) -and $d -ge $windowStart) { '[!] Registered in the last 7 days' })
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($type) { $type } else { 'Unknown' })" -Content ($lines -join "`n")))
        }
        if ($stats.mfaDevices -gt 5) { $b.Add((New-CippReportNote -Text "... and $($stats.mfaDevices - 5) more methods (see the retained investigation record for the full list)")) }
    } else {
        $b.Add((New-CippReportInfoBox -Tone warn -Title '[!] No MFA Devices Found' -Content 'No multi-factor authentication devices are registered. MFA is highly recommended to prevent unauthorized access.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 7: Recent Password Changes'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content "Attackers often change passwords to lock out legitimate users. Reviewing recent password changes in the tenant helps identify if the compromised account's password was changed or if other accounts were affected."))
    if ($stats.passwordChanges -gt 0) {
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($stats.passwordChanges) password change(s) detected in the tenant during the analysis period."))
        foreach ($u in @($bec.ChangedPasswords | Select-Object -First 5)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($u.displayName) { $u.displayName } else { 'Unknown' })" -Content ("Email: $(if ($u.userPrincipalName) { $u.userPrincipalName } else { 'N/A' })`nLast Password Change: $(FmtDate $u.lastPasswordChangeDateTime)")))
        }
        if ($stats.passwordChanges -gt 5) { $b.Add((New-CippReportNote -Text "... and $($stats.passwordChanges - 5) more (see the retained investigation record for the full list)")) }
    } else {
        $b.Add((New-CippReportParagraph -Indent -Text '[i] No password changes detected during the analysis period.'))
    }

    # === PAGE 6: MAILBOX LISTS, DEVICES & LOCATIONS - Check 8,9,10,11 ===
    $b.Add((New-CippReportPage -Title 'Mailbox Lists, Devices & Locations' -Subtitle 'Sender lists, managed devices, and sign-in origins'))
    $b.Add((New-CippReportHeading -Title 'Check 8: Trusted & Blocked Senders'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers may add their own domain to the Trusted Senders list so their fraudulent messages bypass spam filtering, or add finance/security domains to the Blocked Senders list so warnings and alerts are hidden from the victim in the Junk Email folder.'))
    if ($bec.SafelistError) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Could Not Retrieve Sender Lists' -Content ("$($bec.SafelistError)`nAn empty list here does not mean the mailbox has no trusted or blocked senders.")))
    }
    if ($stats.safelistChanges -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.safelistChanges) Safelist Change(s) in the Last $windowDays Days" -Content 'The audit log recorded changes to the Trusted/Blocked Senders and Domains list on this mailbox. Review each change carefully.'))
        foreach ($change in @($bec.SafelistChanges | Select-Object -First 10)) {
            $lines = @(
                "Date: $(FmtDate $change.Date)"
                if ($change.ClientIP) { "From: $($change.ClientIP)$(if ($change.Country) { " ($($change.Country))" })" }
                if ($change.ForeignLocation -eq $true) { '[!] Originated outside the assigned usage location' }
                "Trusted: $(FmtSafelist $change.Trusted)"
                "Blocked: $(FmtSafelist $change.Blocked)"
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Safelist Change' }) by $(if ($change.UserKey) { $change.UserKey } else { 'Unknown' })" -Content ($lines -join "`n")))
        }
        if ($stats.safelistChanges -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.safelistChanges - 10) more changes (see the retained investigation record for the full list)")) }
    }
    if ($stats.trustedSenders -gt 0) {
        $b.Add((New-CippReportInfoBox -Title "Trusted Senders/Domains ($($stats.trustedSenders))" -Content (@($bec.TrustedSenders | Select-Object -First 15) -join ', ')))
    }
    if ($stats.trustedSenders -gt 15) { $b.Add((New-CippReportNote -Text "... and $($stats.trustedSenders - 15) more trusted entries (see the retained investigation record for the full list)")) }
    if ($stats.blockedSenders -gt 0) {
        $b.Add((New-CippReportInfoBox -Title "Blocked Senders/Domains ($($stats.blockedSenders))" -Content (@($bec.BlockedSenders | Select-Object -First 15) -join ', ')))
    }
    if ($stats.blockedSenders -gt 15) { $b.Add((New-CippReportNote -Text "... and $($stats.blockedSenders - 15) more blocked entries (see the retained investigation record for the full list)")) }
    if (-not $bec.SafelistError -and $stats.trustedSenders -eq 0 -and $stats.blockedSenders -eq 0 -and $stats.safelistChanges -eq 0) {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Trusted or Blocked Senders Found' -Content 'No trusted or blocked sender/domain entries were found on this mailbox.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 9: Intune Devices'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Newly enrolled Intune devices can indicate an attacker standing up a VM or BYOD endpoint under the compromised identity, including paths that re-register Windows Hello for Business. Review devices enrolled during the analysis window first.'))
    if ($completeness.IntuneDevices.Skipped) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Intune Not Checked' -Content $(if ($completeness.IntuneDevices.Requirement) { "Not checked - $($completeness.IntuneDevices.Requirement). This is not a pass; the result is unknown." } else { "$($completeness.IntuneDevices.Error)" })))
    } elseif ($bec.IntuneDevicesError) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Could Not Retrieve Intune Devices' -Content ("$(if ($completeness.IntuneDevices.Error) { $completeness.IntuneDevices.Error } else { $bec.IntuneDevicesError })`nAn empty device list here does not mean the user has no Intune devices.")))
    } elseif ($stats.intuneDevices -gt 0) {
        $intuneTail = if ($stats.recentIntuneDevices -gt 0) { ", including $($stats.recentIntuneDevices) enrolled in the last $windowDays days." } else { ". None were enrolled in the last $windowDays days." }
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($stats.intuneDevices) Intune-managed device(s) associated with this user$intuneTail"))
        foreach ($device in @($sortedIntune | Select-Object -First 5)) {
            $lines = @(
                "OS: $(if ($device.operatingSystem) { $device.operatingSystem } else { 'N/A' })$(if ($device.osVersion) { " $($device.osVersion)" })"
                "Enrolled: $(FmtDate $device.enrolledDateTime)"
                "Compliance: $(if ($device.complianceState) { $device.complianceState } else { 'N/A' })"
                "Enrollment Type: $(if ($device.deviceEnrollmentType) { $device.deviceEnrollmentType } else { 'N/A' })"
                if ($device.serialNumber) { "Serial: $($device.serialNumber)" }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($device.deviceName) { $device.deviceName } else { 'Unknown device' })" -Content ($lines -join "`n")))
        }
        if ((Cnt $sortedIntune) -gt 5) { $b.Add((New-CippReportNote -Text "... and $((Cnt $sortedIntune) - 5) more devices (see the retained investigation record for the full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Intune Devices Found' -Content 'No Intune-managed devices were found for this user.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 10: Sign-in Locations'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content ("Sign-ins from countries the user does not work from are one of the strongest compromise indicators. Each sign-in is compared against the user's assigned usage location in Entra ID$(if ($usageLoc) { " ($usageLoc)" }), and the client IPs behind rule changes, safelist changes, sharing changes, and sent mail are geo-located and compared the same way.")))
    if ($bec.SuspectUserSignInsError) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Could Not Retrieve Sign-in Logs' -Content ("$($bec.SuspectUserSignInsError)`nAn empty list here does not mean the user has not signed in.")))
    } else {
        if (-not $usageLoc) {
            $b.Add((New-CippReportInfoBox -Tone warn -Title '[!] No Usage Location Assigned' -Content $(if ($loc.Note) { "$($loc.Note)" } else { 'The user has no usage location assigned in Entra ID, so activity cannot be compared against an expected country.' })))
        }
        if ((Cnt $loc.SignInCountries) -gt 0) {
            $b.Add((New-CippReportInfoBox -Lines -Title "Sign-in Countries Observed (last $($stats.signIns) sign-ins)" -Content ((@($loc.SignInCountries | ForEach-Object { "$($_.Country): $($_.Count) sign-in(s)" })) -join "`n")))
        }
        if ($stats.foreignSignIns -gt 0 -or $stats.foreignActivity -gt 0) {
            $b.Add((New-CippReportAlertBox -Title '[!] Activity Outside the Assigned Usage Location' -Content ("$($stats.foreignSignIns) sign-in(s) (of which $($stats.foreignSuccessfulSignIns) succeeded), $(AsInt $loc.ForeignRuleChangeCount) inbox rule change(s), $(AsInt $loc.ForeignSafelistChangeCount) safelist change(s), $(AsInt $loc.ForeignSharingChangeCount) sharing change(s), and $(AsInt $loc.ForeignSentMessageCount) sent message(s) originated outside $usageLoc. Failed foreign sign-ins are mostly password-spray noise; the successful ones prove access. Review each carefully - a single legitimate trip can explain some of this, but rule, safelist, or sharing changes from a foreign IP rarely have an innocent explanation.")))
            foreach ($signIn in @($foreignSignInList | Select-Object -First 10)) {
                $b.Add((New-CippReportInfoBox -Lines -Title "$(FmtDate $signIn.CreatedDateTime) - $(if ($signIn.Country) { $signIn.Country } else { 'Unknown' })" -Content ("Application: $(if ($signIn.AppDisplayName) { $signIn.AppDisplayName } else { 'N/A' })`nIP Address: $(if ($signIn.IPAddress) { $signIn.IPAddress } else { 'N/A' })`nCity: $(if ($signIn.City) { $signIn.City } else { 'N/A' })`nResult: $(if ($signIn.Status) { $signIn.Status } else { 'N/A' })")))
            }
            if ((Cnt $foreignSignInList) -gt 10) { $b.Add((New-CippReportNote -Text "... and $((Cnt $foreignSignInList) - 10) more foreign sign-ins (see the retained investigation record for the full list)")) }
        } elseif ($usageLoc) {
            $b.Add((New-CippReportClearBox -Title '[Pass] No Foreign Activity Detected' -Content "All located sign-ins and activity match the user's assigned usage location ($usageLoc)."))
        }
    }

    $b.Add((New-CippReportHeading -Title 'Check 11: Sharing Links'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers share OneDrive and SharePoint folders to give themselves a data feed that survives a password reset, and anonymous links expose the content to anyone holding the URL. This check lists every sharing link the account created or changed during the analysis period, including the IP address it was done from.'))
    if ($stats.sharingChanges -gt 0) {
        $anon = if ($stats.anonymousLinks -gt 0) { "$($stats.anonymousLinks) of these involve anonymous links, which anyone with the URL can open. " } else { '' }
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.sharingChanges) Sharing Change(s) in the Last $windowDays Days" -Content ("${anon}Review each link and remove any that are not explained, even if the account has since been remediated.")))
        foreach ($change in @($bec.SharingChanges | Select-Object -First 10)) {
            $lines = @(
                "Date: $(FmtDate $change.Date)"
                "Workload: $(if ($change.Workload) { $change.Workload } else { 'N/A' })"
                if ($change.Target) { "Shared with: $($change.Target)" }
                if ($change.ClientIP) { "From: $($change.ClientIP)$(if ($change.Country) { " ($($change.Country))" })" }
                if ($change.ForeignLocation -eq $true) { '[!] Originated outside the assigned usage location' }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Sharing Change' }): $(if ($change.FileName) { $change.FileName } elseif ($change.ItemUrl) { $change.ItemUrl } else { 'Unknown item' })" -Content ($lines -join "`n")))
        }
        if ($stats.sharingChanges -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.sharingChanges - 10) more changes (see the retained investigation record for the full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Sharing Changes Found' -Content 'No sharing links were created or changed by this account during the analysis period.'))
    }

    # === PAGE 7: FULL INVESTIGATION FINDINGS - Check 12-21 ===
    $b.Add((New-CippReportPage -Title 'Full Investigation Findings' -Subtitle 'Delegations, consents, transport rules, received mail, directory audit, devices and risk state'))

    $b.Add((New-CippReportHeading -Title 'Check 12: Mailbox Delegations and State'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'A delegate with FullAccess or SendAs, a forwarding address, or an automatic reply lets an attacker keep reading and impersonating after the password is changed.'))
    if ($bec.MailboxState.HasForwarding) {
        $fwd = if ($bec.MailboxState.ForwardingSmtpAddress) { $bec.MailboxState.ForwardingSmtpAddress } else { $bec.MailboxState.ForwardingAddress }
        $b.Add((New-CippReportAlertBox -Title '[!] Mail forwarding is configured' -Content ("Mail is forwarded to $fwd$(if ($bec.MailboxState.DeliverToMailboxAndForward) { ' (a copy stays in the mailbox)' }).")))
    }
    if ($flaggedDelegations.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($flaggedDelegations.Count) Flagged Delegation(s)" -Content 'External, guest or catch-all principals hold rights on this mailbox. Remove any the user cannot explain.'))
        foreach ($d in @($flaggedDelegations | Select-Object -First 10)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$($d.PermissionType): $($d.Trustee)" -Content ("Rights: $($d.AccessRights)`nResource: $($d.Resource)")))
        }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Flagged Delegations' -Content "$(Cnt $bec.Delegations) delegation(s) exist, none to an external, guest or catch-all principal."))
    }

    $b.Add((New-CippReportHeading -Title 'Check 13: Application Consents'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Applications the user consented to keep their access after a password reset. A rogue-catalog match or a high-risk scope from an unverified publisher is how mailboxes are synchronised out of the tenant.'))
    if ($flaggedGrants.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($flaggedGrants.Count) Flagged Consent(s)" -Content 'Revoke the grants below unless the user can explain them.'))
        foreach ($g in @($flaggedGrants | Select-Object -First 10)) {
            $lines = @(
                "Scopes: $(if ($g.Scope) { $g.Scope } else { 'N/A' })"
                "Publisher: $(if ($g.Publisher) { $g.Publisher } else { 'Unknown' }) $(if ($g.PublisherVerified) { '(verified)' } else { '(not verified)' })"
                $(if ($g.CatalogMatch.Name) { "Catalog: $($g.CatalogMatch.Name) ($($g.CatalogMatch.Source))" })
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($g.ClientDisplayName) { $g.ClientDisplayName } else { $g.ClientAppId }) ($($g.Risk))" -Content ($lines -join "`n")))
        }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Flagged Consents' -Content "$(Cnt $bec.UserGrants) consent(s) and role assignment(s) exist, none matching the rogue-app catalogs or carrying a high-risk scope from an unverified publisher."))
    }

    $b.Add((New-CippReportHeading -Title 'Check 14: Transport Rules'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'A tenant-wide transport rule that BCCs, redirects, deletes or quarantines mail keeps a feed open after the mailbox itself is cleaned.'))
    if ($flaggedTransportChanges.Count -gt 0 -or $flaggedTransportRules.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($flaggedTransportChanges.Count) risky change(s) in the window, $($flaggedTransportRules.Count) current rule(s) with diversion or suppression actions" -Content 'Review each rule; disable any that cannot be explained.'))
        foreach ($c in @($flaggedTransportChanges | Select-Object -First 5)) {
            $lines = @(
                "Date: $(FmtDate $c.Date)"
                "By: $(if ($c.Actor) { $c.Actor } else { 'Unknown' })"
                if ($c.ClientIP) { "From: $($c.ClientIP)$(if ($c.Country) { " ($($c.Country))" })" }
                "Risky parameters: $(if ($c.RiskyParameters -is [array]) { $c.RiskyParameters -join ', ' } else { $c.RiskyParameters })"
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$($c.Operation): $($c.RuleName)" -Content ($lines -join "`n")))
        }
        foreach ($r in @($flaggedTransportRules | Select-Object -First 5)) {
            $reasons = if ($r.RiskReasons -is [array]) { $r.RiskReasons -join "`n" } else { "$($r.RiskReasons)" }
            $b.Add((New-CippReportInfoBox -Lines -Title "Rule: $($r.Name) ($($r.State), $($r.Mode))" -Content $reasons))
        }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Risky Transport Rules' -Content 'No transport rule with a diversion or suppression action was changed in the window or exists in the tenant.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 15: Mailbox Add-ins'))
    if ($flaggedAddIns.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($flaggedAddIns.Count) user-installed non-Microsoft add-in(s)" -Content ((@($flaggedAddIns | ForEach-Object { "$($_.DisplayName) ($(if ($_.ProviderName) { $_.ProviderName } else { 'unknown provider' }))" })) -join "`n")))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Flagged Add-ins' -Content 'No enabled user-installed add-in from a non-Microsoft provider was found.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 16: Received Mail'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'The message that started the compromise usually arrived in the window. Trace metadata is checked for phishing-shaped subjects and look-alike sender domains; Defender for Office 365 verdicts are included where licensed. No message content is read.'))
    if ($bec.ReceivedMailSummary) {
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($bec.ReceivedMailSummary.TotalMessages) message(s) from $($bec.ReceivedMailSummary.UniqueSenders) sender(s) were received in the window."))
    }
    if ($receivedFindings.Count -gt 0 -or $deliveredThreats.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($receivedFindings.Count) finding(s), $($deliveredThreats.Count) Defender-classified threat(s) delivered" -Content 'Look-alike sender domains are the strongest signal; subject patterns are leads for review, not verdicts.'))
        foreach ($f in @($receivedFindings | Select-Object -First 8)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$($f.FindingType): $($f.SenderAddress)" -Content ("Subject: $(if ($f.Subject) { $f.Subject } else { '(no subject)' })`nReason: $($f.Reason)`nReceived: $(if ($f.Received) { $f.Received } else { 'N/A' }) - $(if ($f.Status) { $f.Status } else { 'N/A' })")))
        }
        foreach ($d in @($deliveredThreats | Select-Object -First 5)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "Defender: $(if ($d.ThreatTypes -is [array]) { $d.ThreatTypes -join ', ' } else { $d.ThreatTypes })" -Content ("From: $(if ($d.SenderAddress) { $d.SenderAddress } else { 'Unknown' })`nSubject: $(if ($d.Subject) { $d.Subject } else { '(no subject)' })`nDelivery: $(if ($d.DeliveryAction) { $d.DeliveryAction } else { 'N/A' }) / $(if ($d.LatestDeliveryLocation) { $d.LatestDeliveryLocation } else { 'N/A' })")))
        }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Received-mail Findings' -Content 'No phishing-shaped subjects, look-alike sender domains or delivered Defender detections were found.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 17: Entra Directory Audit'))
    if ($flaggedAudits.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($flaggedAudits.Count) flagged directory event(s)" -Content 'Security-info registration, consent, service principal, device, password, token or role events involving this user.'))
        foreach ($a in @($flaggedAudits | Select-Object -First 8)) {
            $lines = @(
                "Date: $(FmtDate $a.ActivityDateTime)"
                "By: $(if ($a.InitiatedBy) { $a.InitiatedBy } else { 'Unknown' })"
                if ($a.ClientIP) { "From: $($a.ClientIP)$(if ($a.Country) { " ($($a.Country))" })" }
                if ($a.Targets) { "Targets: $($a.Targets)" }
            )
            $b.Add((New-CippReportInfoBox -Lines -Title "$($a.Activity) ($($a.Result))" -Content ($lines -join "`n")))
        }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Flagged Directory Events' -Content "$(Cnt $bec.DirectoryAudits) directory event(s) involved this user in the window, none of the flagged kinds."))
    }

    $b.Add((New-CippReportHeading -Title 'Check 18 and 19: Registered Devices and Non-interactive Sign-ins'))
    if ($recentRegisteredDevices.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($recentRegisteredDevices.Count) Entra device(s) registered in the window" -Content ((@($recentRegisteredDevices | ForEach-Object { "$(if ($_.displayName) { $_.displayName } else { $_.deviceId }) ($(if ($_.operatingSystem) { $_.operatingSystem } else { 'unknown OS' }), $(if ($_.trustType) { $_.trustType } else { 'unknown trust' })) registered $(FmtDate $_.registrationDateTime)" })) -join "`n")))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Devices Registered in the Window' -Content "$(Cnt $bec.RegisteredDevices) registered device(s), none new."))
    }
    if ($foreignNonInteractive.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($foreignNonInteractive.Count) successful non-interactive sign-in(s) from outside the usage location" -Content ((@($foreignNonInteractive | Select-Object -First 8 | ForEach-Object { "$(FmtDate $_.CreatedDateTime) - $(if ($_.AppDisplayName) { $_.AppDisplayName } else { 'N/A' }) from $(if ($_.IPAddress) { $_.IPAddress } else { 'N/A' }) ($(if ($_.Country) { $_.Country } else { 'Unknown' }))" })) -join "`n")))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Foreign Non-interactive Sign-ins' -Content "$(Cnt $bec.NonInteractiveSignIns) recent non-interactive sign-in(s), none successful from outside the usage location."))
    }

    $b.Add((New-CippReportHeading -Title 'Check 20 and 21: Mailbox Activity and Identity Protection'))
    if ($mailActivitySummary) {
        $lines = @(
            "Item accesses: $($mailActivitySummary.MailItemsAccessedCount)"
            "Hard deletes: $($mailActivitySummary.HardDeleteCount)$(if ($mailActivitySummary.HardDeleteExceeded) { " [!] exceeds the $($mailActivitySummary.HardDeleteThreshold) threshold" })"
            "Soft deletes: $($mailActivitySummary.SoftDeleteCount)"
            "Sends: $($mailActivitySummary.SendCount)"
            "Distinct client IPs: $($mailActivitySummary.DistinctClientIPs)"
            $(if ($mailActivitySummary.SendAsByOthersCount -gt 0) { "Sent as/on behalf by others: $($mailActivitySummary.SendAsByOthersCount)" })
            'Counts only - no items were read.'
        )
        $b.Add((New-CippReportInfoBox -Lines -Tone $(if ($mailActivitySummary.HardDeleteExceeded) { 'warn' } else { '' }) -Title 'Mailbox activity counts' -Content ($lines -join "`n")))
    } else {
        $b.Add((New-CippReportNote -Text 'Mailbox activity counts were not available for this run.'))
    }
    if ($completeness.RiskState.Skipped) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Identity Protection Not Checked' -Content $(if ($completeness.RiskState.Requirement) { "Not checked - $($completeness.RiskState.Requirement). This is not a pass; whether the account is flagged as risky is unknown." } else { "$($completeness.RiskState.Error)" })))
    } elseif ($riskState.Listed) {
        $b.Add((New-CippReportAlertBox -Title "[!] Identity Protection: $($riskState.RiskState) at $($riskState.RiskLevel) risk" -Content ("$(if ($riskState.RiskDetail) { $riskState.RiskDetail } else { 'No detail' }) - last updated $(FmtDate $riskState.RiskLastUpdatedDateTime).$(if ((Cnt $riskState.Detections) -gt 0) { " $(Cnt $riskState.Detections) risk detection(s) in the window." })")))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] Not Listed as Risky' -Content 'Identity Protection does not list this user as risky.'))
    }

    # === PAGE 8: RECOMMENDATIONS ===
    $b.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'Actions to take and prevention best practices'))
    $b.Add((New-CippReportParagraph -Title 'Immediate Actions Required' -Text 'Based on the investigation findings, the following actions should be taken immediately:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ marker = '1.'; label = 'Reset Password:'; text = "Change the user's password immediately to prevent further unauthorized access." }
                @{ marker = '2.'; label = 'Revoke Sessions:'; text = 'Sign out the user from all active sessions to terminate any attacker access.' }
                @{ marker = '3.'; label = 'Remove Suspicious Rules:'; text = 'Delete any mailbox rules that forward, redirect, or hide emails, especially those moving messages to unusual folders.' }
                @{ marker = '4.'; label = 'Review MFA Devices:'; text = "Remove any MFA devices that the user doesn't recognize and re-register legitimate devices." }
                @{ marker = '5.'; label = 'Audit Permissions:'; text = 'Review and revoke any unauthorized mailbox permissions or application consents.' }
                @{ marker = '6.'; label = 'Monitor Account:'; text = 'Continue monitoring the account for suspicious activity for at least 30 days.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Long-Term Prevention Strategies' -Text 'To prevent future Business Email Compromise attacks, implement these security best practices:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'Enforce Multi-Factor Authentication (MFA):'; text = 'Require MFA for all users, especially those with administrative privileges or access to financial systems.' }
                @{ label = 'Implement Security Awareness Training:'; text = 'Educate employees about phishing, social engineering, and how to identify suspicious emails. Regular training significantly reduces successful attacks.' }
                @{ label = 'Enable Advanced Threat Protection:'; text = 'Use email security solutions that detect and block phishing, malware, and suspicious attachments.' }
                @{ label = 'Configure Conditional Access Policies:'; text = 'Restrict access based on location, device compliance, and risk level to prevent unauthorized sign-ins.' }
                @{ label = 'Monitor Audit Logs:'; text = 'Regularly review audit logs for suspicious activities such as unusual sign-in patterns, rule creation, or permission changes.' }
                @{ label = 'Establish Financial Controls:'; text = 'Implement multi-person approval processes for wire transfers and payment changes to prevent fraudulent transactions.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'User Education Points' -Text 'Share these key points with the affected user to help prevent future compromises:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ text = 'Never click on links or open attachments in unexpected emails, even if they appear to come from known contacts.' }
                @{ text = 'Always verify unusual requests for money transfers or sensitive information through a separate communication channel (phone call, in person).' }
                @{ text = 'Use strong, unique passwords for each account and consider using a password manager.' }
                @{ text = 'Be cautious when authorizing new applications or granting permissions to third-party services.' }
                @{ text = 'Report suspicious emails or activities to your IT security team immediately.' }
            )))

    # === PAGE 9: COMPLIANCE & DOCUMENTATION ===
    $b.Add((New-CippReportPage -Title 'Compliance & Documentation' -Subtitle 'Meeting regulatory and audit requirements'))
    $b.Add((New-CippReportParagraph -Title 'Compliance Considerations' -Text 'This report supports compliance and documentation requirements for various security frameworks and regulatory standards:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'ISO 27001:'; text = 'Demonstrates incident detection, analysis, and response procedures (Controls A.16.1.1 - A.16.1.7).' }
                @{ label = 'CMMC Level 2:'; text = 'Provides evidence of security incident monitoring, analysis, and documentation (AC.L2-3.1.12, AU.L2-3.3.1).' }
                @{ label = 'SOC 2 Type II:'; text = 'Documents detective and responsive controls for security incidents (CC7.3, CC7.4).' }
                @{ label = 'NIST CSF:'; text = 'Aligns with Detect (DE.AE, DE.CM) and Respond (RS.AN, RS.MI) functions.' }
                @{ label = 'GDPR:'; text = 'Demonstrates security breach detection and potential data breach assessment (Articles 32, 33).' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Audit Trail' -Text 'This investigation and resulting documentation provide an audit trail for security incident response:'))
    $b.Add((New-CippReportInfoBox -Lines -Title 'Investigation Details' -Content (@(
                    "Investigation Date: $(FmtDate $bec.ExtractedAt)"
                    "Analyzed User: $upn"
                    "Organization: $TenantName"
                    "Analysis Period: $windowDays days"
                    "Assigned Usage Location: $(if ($usageLoc) { $usageLoc } else { 'Not assigned' })"
                    "Audit Log Status: $(if ($bec.ExtractResult) { $bec.ExtractResult } else { 'Unknown' })"
                ) -join "`n")))
    $b.Add((New-CippReportInfoBox -Lines -Title 'Findings Summary' -Content (@(
                    "Threat Level: $threatLevel (score $threatValue)"
                    "Mailbox Rules Found: $($stats.newRules)"
                    "Rule Changes: $($stats.ruleChanges)"
                    "Permission Changes: $($stats.permissionChanges) ($($stats.permissionChangesTargetingUser) targeting this mailbox)"
                    "New Applications: $($stats.newApps)"
                    "Known-Malicious Applications: $($stats.maliciousApps)"
                    "Flagged Application Consents: $($flaggedGrants.Count)"
                    "Flagged Mailbox Delegations: $($flaggedDelegations.Count)"
                    "Flagged Transport Rules/Changes: $($flaggedTransportRules.Count + $flaggedTransportChanges.Count)"
                    "New Users: $($stats.newUsers)"
                    "Sent Messages: $(if ($stats.sentTotalMessages) { $stats.sentTotalMessages } else { $stats.sentMessages })"
                    "Repeated Subject Campaigns: $($stats.repeatedSubjects)"
                    "Send Bursts: $($stats.sendBursts)"
                    "MFA Devices: $($stats.mfaDevices)"
                    "Recent MFA Registrations ($windowDays d): $($stats.recentMfaDevices)"
                    "Password Changes: $($stats.passwordChanges)"
                    "Trusted Senders: $($stats.trustedSenders)"
                    "Blocked Senders: $($stats.blockedSenders)"
                    "Safelist Changes: $($stats.safelistChanges)"
                    "Sharing Changes: $($stats.sharingChanges)"
                    "Anonymous Links: $($stats.anonymousLinks)"
                    "Intune Devices: $($stats.intuneDevices)"
                    "Recent Intune Enrollments ($windowDays d): $($stats.recentIntuneDevices)"
                    "Received-mail Findings: $($receivedFindings.Count)"
                    "Delivered Threats: $($deliveredThreats.Count)"
                    "Foreign Sign-ins: $($stats.foreignSignIns) ($($stats.foreignSuccessfulSignIns) successful)"
                    "Foreign Non-interactive Sign-ins: $($foreignNonInteractive.Count)"
                    "Identity Protection Listed: $(if ($riskState.Listed) { "Yes ($($riskState.RiskLevel))" } else { 'No' })"
                ) -join "`n")))
    $b.Add((New-CippReportParagraph -Title 'Document Retention' -Text "This report should be retained according to your organization's document retention policy and regulatory requirements. Typical retention periods range from 3-7 years depending on applicable compliance frameworks. Store this document securely with restricted access as it contains sensitive security information."))
    $b.Add((New-CippReportParagraph -Title 'Additional Resources' -Text 'For more information about Business Email Compromise and cybersecurity best practices:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ text = 'FBI IC3: Internet Crime Complaint Center (ic3.gov)' }
                @{ text = 'CISA: Cybersecurity & Infrastructure Security Agency (cisa.gov)' }
                @{ text = 'Microsoft Security: Business Email Compromise resources' }
            )))
    }

    @{
        Blocks    = @($b)
        Variables = @{
            coverlabel         = 'Security Incident Report'
            covertitle         = 'BEC Compromise'
            coveraccent        = 'Analysis'
            covertenant        = [string]$UserData.displayName
            coversubtitle      = "Business Email Compromise Investigation Report for $TenantName"
            covermeta          = [string]$upn
            covermetanote      = "Analysis Date: $(FmtDate $bec.ExtractedAt)"
            coverfallbackimage = '/reportImages/soc.jpg'
            coverfooternote    = 'Confidential & Proprietary - For Internal Use Only'
            footerlabel        = "$TenantName - BEC Analysis Report for $($UserData.displayName)"
        }
    }
}
