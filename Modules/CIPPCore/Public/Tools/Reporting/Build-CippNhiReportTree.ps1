function Build-CippNhiReportTree {
    <#
    .SYNOPSIS
        Compose the non-human identity (NHI) compromise report as a component tree.
    .DESCRIPTION
        Returns @{ Blocks; Variables } for ConvertTo-CippReportPdf from a completed NHI run's results
        (Push-NHIRun) and its containment history. The cover names the app. An executive section (case
        level, what was found, findings at a glance, priority actions, order of events and containment
        already run) leads; the detail follows: addresses, credentials, changes and actions, mail and
        files, access and owners. The level is the server-computed Score on the run. The app in the
        other tenants is never included: the report is about this tenant and may go to its customer.
    .PARAMETER NhiData
        The completed NHI results payload (NhiResults).
    .PARAMETER Containment
        The run's containment history (the Containment entries of its NhiReports row).
    .PARAMETER TenantName
        The tenant the app belongs to.
    .PARAMETER Variant
        full (every page) or summary (the cover and the executive summary, for a C-suite reader).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$NhiData, $Containment, [string]$TenantName, [ValidateSet('full', 'summary')][string]$Variant = 'full')

    $IsSummary = $Variant -eq 'summary'
    $Nhi = $NhiData
    $Subject = $Nhi.Subject
    $Exposure = $Nhi.Exposure
    $Score = $Nhi.Score
    $WindowDays = if ($Nhi.AnalysisWindowDays) { [int]$Nhi.AnalysisWindowDays } else { 7 }
    $BaselineDays = [int]$Nhi.BaselineDays
    $AppName = if ($Nhi.DisplayName) { [string]$Nhi.DisplayName } elseif ($Subject.DisplayName) { [string]$Subject.DisplayName } else { [string]$Nhi.AppId }
    $IsManagedIdentity = [bool]$Subject.IsManagedIdentity
    $Kind = if ($IsManagedIdentity) { 'managed identity' } else { 'app' }
    $KindTitle = if ($IsManagedIdentity) { 'Managed Identity' } else { 'App' }
    $AKind = if ($IsManagedIdentity) { 'a managed identity' } else { 'an app' }

    # Times in the instance timezone, as the cover date and the other server reports
    $TimeZoneId = [System.Environment]::GetEnvironmentVariable('CIPP_TIMEZONE')
    $Zone = [TimeZoneInfo]::Utc
    if ($TimeZoneId) {
        try { $Zone = [TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId) } catch { Write-Information "NHI report: unknown timezone '$TimeZoneId', dating events in UTC" }
    }
    $Invariant = [Globalization.CultureInfo]::InvariantCulture
    # Graph times are UTC; a parsed time without a zone is UTC wall time too
    $ToTime = {
        param($Value)
        if (-not $Value) { return $null }
        try {
            if ($Value -is [DateTimeOffset]) { $Value }
            elseif ($Value -is [datetime]) { if ($Value.Kind -eq [DateTimeKind]::Unspecified) { [DateTimeOffset]::new([datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)) } else { [DateTimeOffset]$Value } }
            else { [DateTimeOffset]::Parse([string]$Value, $Invariant, [Globalization.DateTimeStyles]::AssumeUniversal) }
        } catch { $null }
    }
    $FormatDate = {
        param($Value)
        $Time = & $ToTime $Value
        if ($Time) { [TimeZoneInfo]::ConvertTime($Time, $Zone).ToString('MMM d, yyyy, hh:mm tt', $Invariant) } elseif ($Value) { [string]$Value } else { '' }
    }
    $ListNames = {
        param($Names, [int]$Max = 3)
        $All = @($Names | Where-Object { $_ })
        (@($All | Select-Object -First $Max) -join ', ') + $(if ($All.Count -gt $Max) { " and $($All.Count - $Max) more" } else { '' })
    }
    $WindowStart = & $ToTime $Nhi.StartDate

    # -- the score's signals, by name --
    $Level = if ($Score.Level) { [string]$Score.Level } else { 'Low' }
    $LevelColour = @{ Critical = '#63171B'; High = '#742A2A'; Medium = '#744210'; Low = '#22543D' }[$Level]
    if (-not $LevelColour) { $LevelColour = '#22543D' }
    $Applied = @($Score.Breakdown | Where-Object { $_ -and $_.Applied })
    $SignalCount = @{}
    foreach ($Signal in $Applied) { $SignalCount[[string]$Signal.Signal] = [int]$Signal.Count }

    # -- addresses --
    $AttackerVerdicts = @('Compromised', 'LikelyAttacker')
    $Verdicts = @($Nhi.IPVerdicts | Where-Object { $_ -and $_.IP })
    $AttackerIPs = @($Verdicts.Where({ $_.Verdict -in $AttackerVerdicts }))
    $SuspiciousIPs = @($Verdicts.Where({ $_.Verdict -eq 'Suspicious' }))
    $ReviewIPs = @($AttackerIPs) + @($SuspiciousIPs)
    $AttackerCountries = [System.Collections.Generic.List[string]]::new()
    $AttackerSignIns = 0
    $ActiveAttackerIPs = 0
    foreach ($Verdict in $AttackerIPs) {
        if ($Verdict.Country -and -not $AttackerCountries.Contains([string]$Verdict.Country)) { $AttackerCountries.Add([string]$Verdict.Country) }
        $AttackerSignIns = $AttackerSignIns + [int]$Verdict.SuccessfulSignIns
        if ([int]$Verdict.SuccessfulSignIns -gt 0 -or [int]$Verdict.Activities -gt 0) { $ActiveAttackerIPs++ }
    }

    # -- credentials --
    $FlaggedKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Nhi.FlaggedKeyIds | Where-Object { $_ }), [System.StringComparer]::OrdinalIgnoreCase)
    $Credentials = @($Exposure.CredentialDetails | Where-Object { $_ })
    $FlaggedCredentials = @($Credentials.Where({ $_.KeyId -and $FlaggedKeys.Contains([string]$_.KeyId) -and $_.Type -ne 'Federated' }))
    $UntrustedFederated = @($Credentials.Where({ @($_.Flags) -contains 'UntrustedIssuer' }))
    $FlaggedCredentialSignIns = @($Nhi.SignInsByCredential | Where-Object { $_ -and $_.KeyId -and $FlaggedKeys.Contains([string]$_.KeyId) -and [int]$_.Success -gt 0 })
    $UsedFlaggedKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($FlaggedCredentialSignIns | ForEach-Object { [string]$_.KeyId }), [System.StringComparer]::OrdinalIgnoreCase)
    $UsedFlaggedCredentials = @($FlaggedCredentials.Where({ $UsedFlaggedKeys.Contains([string]$_.KeyId) }))
    $FlagLabels = @{ AddedRecently = 'added recently'; AddedByApp = 'added by another app'; Backdated = 'backdated'; UntrustedIssuer = 'untrusted issuer'; Rotation = 'rotation' }

    # -- changes to the app and what it did in the directory --
    $Changes = @($Nhi.Changes | Where-Object { $_ })
    $FlaggedChanges = @($Changes.Where({ $_.Flagged -and $_.InWindow }))
    $OwnersAdded = @($FlaggedChanges.Where({ $_.Kind -eq 'Owner' }))
    $RedirectChanges = @($FlaggedChanges.Where({ $_.Kind -eq 'RedirectUri' }))
    $AudienceChanges = @($FlaggedChanges.Where({ $_.Kind -eq 'Audience' }))
    $DirectoryActions = @($Nhi.DirectoryActions | Where-Object { $_ })
    $Elevations = @($DirectoryActions.Where({ $_.Kind -eq 'Elevation' }))
    $ElevationsInWindow = @($Elevations.Where({ $_.InWindow }))
    $HighElevations = @($ElevationsInWindow.Where({ $_.Impact -in 'High', 'Critical' }))
    $Persistence = @($DirectoryActions.Where({ $_.Kind -eq 'AppPersistence' }))
    $PersistenceInWindow = @($Persistence.Where({ $_.InWindow }))
    $OtherActions = @($DirectoryActions.Where({ $_.Kind -ne 'Elevation' -and $_.Kind -ne 'AppPersistence' -and $_.InWindow -and $_.Severity -ne 'Info' }))
    $PermissionsInWindow = @($Nhi.AppRoleAssignments | Where-Object { $_ -and $_.InWindow })
    $ConsentsInWindow = @($Nhi.Consents | Where-Object { $_ -and (-not $WindowStart -or (& $ToTime $_.ActivityDateTime) -ge $WindowStart) })
    $Risk = $Nhi.RiskState
    $Workload = $Nhi.WorkloadSummary
    $WorkloadActivity = $Nhi.WorkloadActivity
    $Rogue = $Nhi.RogueMatch
    $DisabledByMicrosoft = [string]$Exposure.DisabledByMicrosoftStatus

    # ============================================================================================
    # What was found, in plain terms
    # ============================================================================================
    $Found = @(
        if ($Rogue) { "The $Kind is listed in the rogue-app catalog as $($Rogue.Name)$(if (@($Rogue.Categories).Count) { " ($(@($Rogue.Categories) -join ', '))" })." }
        if ($DisabledByMicrosoft) { "Microsoft has disabled the $Kind as malicious or abusive." }
        if ($Risk.riskState -eq 'confirmedCompromised') { "An administrator confirmed the $Kind compromised in Microsoft Identity Protection." }
        elseif ($Risk.riskState -eq 'atRisk') { "Microsoft Identity Protection rates the $Kind at $($Risk.riskLevel) risk." }
        if ($AttackerIPs.Count) { "$($AttackerIPs.Count) network address(es)$(if ($AttackerCountries.Count) { " in $(& $ListNames $AttackerCountries)" }) were judged the attacker's; the $Kind signed in successfully $AttackerSignIns time(s) from them." }
        if ($FlaggedCredentials.Count) { "$($FlaggedCredentials.Count) of the $Kind's credentials are flagged: added in the window, by another app, or backdated$(if ($UsedFlaggedCredentials.Count) { ", and $($UsedFlaggedCredentials.Count) of them signed in" })." }
        if ($UntrustedFederated.Count) { "$($UntrustedFederated.Count) federated credential(s) let an identity provider CIPP does not recognise, or another Entra tenant, sign in as the $Kind." }
        if ($HighElevations.Count) { "The $Kind granted $($HighElevations.Count) high-impact permission(s) or directory role(s) ($(& $ListNames @($HighElevations | ForEach-Object { $_.Permission }))). That access stays after the $Kind is disabled." }
        if ($PersistenceInWindow.Count) { "The $Kind created apps, or put credentials or owners on other apps, $($PersistenceInWindow.Count) time(s) ($(& $ListNames @($PersistenceInWindow | ForEach-Object { $_.TargetDisplayName } | Select-Object -Unique))). Each can keep access after this $Kind is disabled." }
        if ($OwnersAdded.Count) { "$($OwnersAdded.Count) owner(s) were added in the window. An owner can add a credential and act with the $Kind's access." }
        if ($RedirectChanges.Count) { "The redirect URIs, where sign-in codes and tokens are sent, were changed $($RedirectChanges.Count) time(s) in the window." }
        if ($AudienceChanges.Count) { 'The app was opened to other organisations in the window.' }
        if ($SignalCount.ContainsKey('MassMailboxAccess') -or $SignalCount.ContainsKey('MassFileAccess') -or $SignalCount.ContainsKey('AttackerWorkload')) { "The $Kind reached $([int]$Workload.MailboxCount) mailbox(es) ($([int]$Workload.MailItemCount) mail item(s)) and $([int]$Workload.FileCount) file(s) on $([int]$Workload.SiteCount) site(s) in the window, more than it reached before." }
        if ($SignalCount.ContainsKey('NewMailSending')) { "The $Kind sent $($SignalCount['NewMailSending']) message(s), which it did not do before the window." }
        if ($SignalCount.ContainsKey('NewAnonymousLinks')) { "The $Kind created $($SignalCount['NewAnonymousLinks']) 'anyone' sharing link(s), which expose files to whoever holds the link." }
        if ([int]$Workload.RuleCount -gt 0) { "The $Kind created or changed $([int]$Workload.RuleCount) inbox rule(s)." }
        if ($SignalCount.ContainsKey('ConsentBurst')) { "$($SignalCount['ConsentBurst']) users consented to the app in the window, a pattern seen in consent phishing." }
        if ($SignalCount.ContainsKey('DormantAwakened')) { "The $Kind had not signed in for the $BaselineDays days before the window, then signed in during it." }
    )

    # ============================================================================================
    # Results roll-up: every check as one row, flagged (with a high-risk sub-count) or clear
    # ============================================================================================
    $SummarySource = @(
        @{ area = 'Rogue-app catalog and Microsoft'; count = [int][bool]$Rogue + [int][bool]$DisabledByMicrosoft; danger = [int][bool]$Rogue + [int][bool]$DisabledByMicrosoft }
        @{ area = 'Identity Protection risk'; count = [int]($Risk.riskState -in 'atRisk', 'confirmedCompromised'); danger = [int]($Risk.riskState -eq 'confirmedCompromised' -or $Risk.riskLevel -eq 'high') }
        @{ area = 'Attacker network addresses'; count = $AttackerIPs.Count; danger = $ActiveAttackerIPs }
        @{ area = 'Suspicious network addresses'; count = $SuspiciousIPs.Count }
        @{ area = 'Flagged credentials'; count = $FlaggedCredentials.Count + $UntrustedFederated.Count; danger = $UsedFlaggedCredentials.Count + $UntrustedFederated.Count }
        @{ area = 'Changes to the app (in window)'; count = $FlaggedChanges.Count }
        @{ area = 'Permissions granted to the app (in window)'; count = $PermissionsInWindow.Count }
        @{ area = 'Access the app granted (in window)'; count = $ElevationsInWindow.Count; danger = $HighElevations.Count }
        @{ area = 'Apps it created or took over (in window)'; count = $PersistenceInWindow.Count; danger = $PersistenceInWindow.Count }
        @{ area = 'Other directory changes (in window)'; count = $OtherActions.Count; danger = @($OtherActions.Where({ $_.Severity -eq 'Critical' })).Count }
        @{ area = 'Mailboxes and files beyond its usual reach'; count = [int]$SignalCount['MassMailboxAccess'] + [int]$SignalCount['MassFileAccess'] }
        @{ area = 'Mail and file activity from attacker addresses'; count = [int]$SignalCount['AttackerWorkload']; danger = [int]$SignalCount['AttackerWorkload'] }
        @{ area = 'Inbox rules'; count = [int]$Workload.RuleCount; danger = [int]$Workload.RuleCount }
        @{ area = 'New mail sending or anyone links'; count = [int]$SignalCount['NewMailSending'] + [int]$SignalCount['NewAnonymousLinks'] }
        @{ area = 'User consents (in window)'; count = $ConsentsInWindow.Count; danger = [int]$SignalCount['ConsentBurst'] }
    )
    $SummaryRows = @(foreach ($Row in $SummarySource) {
            $Danger = [int]$Row.danger
            $Flagged = [int]$Row.count
            @{
                area   = $Row.area
                result = if ($Danger -gt 0) { "$Flagged flagged - $Danger high-risk" } elseif ($Flagged -gt 0) { "$Flagged flagged" } else { 'Clear' }
                tone   = if ($Danger -gt 0) { 'fail' } elseif ($Flagged -gt 0) { 'warn' } else { 'pass' }
            }
        })
    $FlaggedAreas = @($SummaryRows.Where({ $_.result -ne 'Clear' })).Count

    # ============================================================================================
    # Priority actions, written from what was found (the containment drawer runs most of them)
    # ============================================================================================
    $Serious = $Level -in 'High', 'Critical' -or $AttackerIPs.Count -gt 0 -or $FlaggedCredentialSignIns.Count -gt 0 -or $Rogue -or $Risk.riskState -eq 'confirmedCompromised'
    $PriorityActions = @(
        if ($Serious -and $IsManagedIdentity) { @{ tag = 'Critical'; text = "Remove the managed identity from its Azure resource$(if ($Subject.AzureResourceId) { " ($($Subject.AzureResourceId))" }), or stop the resource: Azure manages its credentials, so it cannot be disabled in Microsoft Entra ID." } }
        elseif ($Serious -and $Subject.AccountEnabled -ne $false) { @{ id = 'DisableServicePrincipal'; tag = 'Critical'; text = "Disable $AppName in this tenant so it gets no new tokens. Tokens already issued stay valid for about an hour, so remove its credentials as well." } }
        if ($FlaggedCredentials.Count) { @{ id = 'RemoveCredentials'; tag = 'Critical'; text = "Remove the $($FlaggedCredentials.Count) flagged credential(s) ($(& $ListNames @($FlaggedCredentials | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.KeyId } }))). A credential keeps working whatever else is changed." } }
        if ($UntrustedFederated.Count) { @{ id = 'RemoveFederatedCredentials'; tag = 'High'; text = "Remove the $($UntrustedFederated.Count) federated credential(s) trusting an unrecognised identity provider ($(& $ListNames @($UntrustedFederated | ForEach-Object { if ($_.DisplayName) { $_.DisplayName } else { $_.Issuer } })))." } }
        if ($HighElevations.Count) { @{ id = 'RevokeElevation'; tag = 'Critical'; text = "Revoke the $($HighElevations.Count) high-impact permission(s) or role(s) the $Kind granted ($(& $ListNames @($HighElevations | ForEach-Object { "$($_.Permission) to $(if ($_.Recipient -eq 'Self') { 'itself' } elseif ($_.RecipientName) { $_.RecipientName } else { $_.RecipientId })" }))), and investigate each recipient." } }
        if ($PersistenceInWindow.Count) { @{ id = 'DisablePersistenceApps'; tag = 'Critical'; text = "Investigate, and disable where safe, the apps the $Kind created or put credentials or owners on ($(& $ListNames @($PersistenceInWindow | ForEach-Object { $_.TargetDisplayName } | Select-Object -Unique))). Microsoft's and CIPP's own apps are never disabled: remove the credential they were given instead." } }
        if ($PermissionsInWindow.Count) { @{ id = 'RevokeAppRoleAssignments'; tag = 'High'; text = "Review the $($PermissionsInWindow.Count) application permission(s) granted to the $Kind in the window ($(& $ListNames @($PermissionsInWindow | ForEach-Object { "$($_.ResourceDisplayName) $($_.Permission)" }))) and revoke any that were not planned." } }
        if ($OwnersAdded.Count) { @{ id = 'RemoveOwners'; tag = 'High'; text = "Review the $($OwnersAdded.Count) owner(s) added in the window and remove any that were not planned: an owner can add a credential." } }
        if ($RedirectChanges.Count) { @{ tag = 'High'; text = 'Restore the redirect URIs changed in the window: sign-in codes and tokens are sent there.' } }
        if ($AttackerIPs.Count) { @{ tag = 'High'; text = "Block the $($AttackerIPs.Count) attacker address(es) ($(& $ListNames @($AttackerIPs | ForEach-Object { $_.IP }))) tenant-wide." } }
        if ([int]$Workload.RuleCount -gt 0) { @{ tag = 'High'; text = "Remove the $([int]$Workload.RuleCount) inbox rule(s) the $Kind created or changed, and check the mailboxes they are on." } }
        if ($SignalCount.ContainsKey('NewAnonymousLinks')) { @{ tag = 'High'; text = "Remove the $($SignalCount['NewAnonymousLinks']) 'anyone' sharing link(s) the $Kind created." } }
        if ($SignalCount.ContainsKey('NewMailSending')) { @{ tag = 'High'; text = "Scope the $($SignalCount['NewMailSending']) message(s) the $Kind sent and warn the recipients." } }
        if ($SignalCount.ContainsKey('ConsentBurst')) { @{ tag = 'High'; text = "Revoke the delegated consents the $($SignalCount['ConsentBurst']) users gave in the window and tell them the app is not trusted." } }
        if ($AudienceChanges.Count) { @{ tag = 'Medium'; text = 'Return the app to single-organisation use unless opening it to other organisations was planned.' } }
        if ($Risk.riskState -eq 'atRisk') { @{ id = 'ConfirmCompromised'; tag = 'Medium'; text = "Once the investigation agrees, confirm the $Kind compromised in Identity Protection so risk-based Conditional Access blocks it." } }
        if ($Serious -and $Subject.IsOwnApp -and $Subject.AppSignInAudience -and $Subject.AppSignInAudience -ne 'AzureADMyOrg' -and $Subject.PropertyLock -ne $true) { @{ id = 'LockAppInstanceProperties'; tag = 'Medium'; text = 'Lock the app instance properties so no organisation the app is consented in can add a credential to its copy.' } }
    )
    if ($PriorityActions.Count -eq 0) {
        $PriorityActions = @(@{ tag = 'Monitor'; text = "No indicator requires action. Keep reviewing the $Kind's credentials and permissions, and run a new investigation if its behaviour changes." })
    }
    # Containment in force, by action id: when it last ran without an error, unless a release has undone it since
    $ContainmentHistory = @($Containment | Where-Object { $_ } | Sort-Object -Property { & $ToTime $_.At })
    $CompletedAt = @{}
    foreach ($Entry in $ContainmentHistory) {
        $EntryResults = @($Entry.Results | Where-Object { $_ -and $_.Action })
        if ($Entry.Kind -eq 'Release') {
            foreach ($Result in $EntryResults) { if ($Result.state -eq 'success') { $CompletedAt.Remove([string]$Result.Action) } }
            continue
        }
        $Failed = @{}
        foreach ($Result in $EntryResults) { if ($Result.state -eq 'error') { $Failed[[string]$Result.Action] = $true } }
        foreach ($Result in $EntryResults) { $CompletedAt[[string]$Result.Action] = if ($Failed[[string]$Result.Action]) { $null } else { & $ToTime $Entry.At } }
    }
    $PriorityRows = @(foreach ($Action in $PriorityActions) {
            $Done = if ($Action.id) { $CompletedAt[$Action.id] } else { $null }
            @{ tag = $Action.tag; text = $(if ($Done) { "$($Action.text)`nCompleted $(& $FormatDate $Done)" } else { $Action.text }); tone = switch ($Action.tag) { 'Critical' { 'fail' } 'High' { 'fail' } 'Medium' { 'warn' } default { 'pass' } } }
        })

    # ============================================================================================
    # Order of events: every dated signal of the window, oldest first
    # ============================================================================================
    $Events = [System.Collections.Generic.List[object]]::new()
    if ($WindowStart -and ($Created = & $ToTime $Subject.CreatedDateTime) -and $Created -ge $WindowStart) {
        $Events.Add([pscustomobject]@{ Time = $Created; Event = "The $Kind was added to the tenant"; Detail = '' })
    }
    foreach ($Change in $Changes) {
        if (-not $Change.InWindow -or -not ($Change.Flagged -or $Change.Kind -in 'Created', 'Enabled')) { continue }
        $Events.Add([pscustomobject]@{ Time = & $ToTime $Change.ActivityDateTime; Event = [string]$Change.Activity; Detail = (@("by $($Change.InitiatedBy)", $Change.Detail, $Change.ClientIP) | Where-Object { $_ -and $_ -ne 'by ' }) -join ' - ' })
    }
    foreach ($Action in $DirectoryActions) {
        if (-not $Action.InWindow -or $Action.Severity -eq 'Info') { continue }
        $Detail = if ($Action.Kind -eq 'Elevation') { "$($Action.Permission) to $(if ($Action.Recipient -eq 'Self') { 'itself' } else { $Action.RecipientName })" }
        elseif ($Action.Kind -eq 'AppPersistence') { [string]$Action.TargetDisplayName }
        else { (@($Action.Targets | ForEach-Object { if ($_.UserPrincipalName) { $_.UserPrincipalName } else { $_.DisplayName } } | Where-Object { $_ }) | Select-Object -First 3) -join ', ' }
        $Events.Add([pscustomobject]@{ Time = & $ToTime $Action.ActivityDateTime; Event = [string]$Action.Activity; Detail = $Detail })
    }
    foreach ($Verdict in $AttackerIPs) {
        $Place = (@($Verdict.City, $Verdict.Country, $Verdict.ASName) | Where-Object { $_ }) -join ', '
        $Events.Add([pscustomobject]@{ Time = & $ToTime $Verdict.FirstSeen; Event = 'First sign-in from an attacker address'; Detail = (@($Verdict.IP, $Place) | Where-Object { $_ }) -join ' - ' })
    }
    foreach ($Detection in @($Nhi.RiskDetections | Where-Object { $_ })) {
        $When = & $ToTime ($Detection.activityDateTime ?? $Detection.detectedDateTime)
        if ($WindowStart -and $When -and $When -lt $WindowStart) { continue }
        $Events.Add([pscustomobject]@{ Time = $When; Event = 'Identity Protection risk detection'; Detail = (@($Detection.riskEventType, $Detection.riskLevel, $Detection.ipAddress) | Where-Object { $_ }) -join ' - ' })
    }
    foreach ($Consent in $ConsentsInWindow) {
        $Events.Add([pscustomobject]@{ Time = & $ToTime $Consent.ActivityDateTime; Event = 'A user consented to the app'; Detail = (@($Consent.User, $Consent.ClientIP) | Where-Object { $_ }) -join ' - ' })
    }
    foreach ($Rule in @($WorkloadActivity.InboxRules | Where-Object { $_ })) {
        $Events.Add([pscustomobject]@{ Time = & $ToTime $Rule.CreationTime; Event = [string]$Rule.Operation; Detail = (@($Rule.Mailbox, $Rule.ClientIP) | Where-Object { $_ }) -join ' - ' })
    }
    $SortedEvents = @($Events.Where({ $_.Time }) | Sort-Object -Property Time)
    $TimelineLimit = 40
    $TimelineRows = @(foreach ($TimelineEvent in @($SortedEvents | Select-Object -First $TimelineLimit)) {
            @{ when = (& $FormatDate $TimelineEvent.Time); event = $TimelineEvent.Event; detail = [string]$TimelineEvent.Detail }
        })

    # -- containment already run --
    $NewestFirst = [object[]]$ContainmentHistory.Clone()
    [array]::Reverse($NewestFirst)
    $RemediationRows = @(foreach ($Entry in $NewestFirst) {
            foreach ($Result in @($Entry.Results | Where-Object { $_ })) {
                $State = [string]$Result.state
                @{
                    when   = (& $FormatDate $Entry.At)
                    action = "$(if ($Entry.Kind -eq 'Release') { 'Release: ' })$(([string]$Result.Action -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim())"
                    target = [string]$Result.Target
                    result = [string]$Result.resultText
                    state  = $State
                    tone   = switch ($State) { 'success' { 'pass' } 'error' { 'fail' } 'warning' { 'warn' } default { '' } }
                }
            }
        })

    # -- checks that did not run, or ran partly (the lookup in other tenants is not part of this report) --
    $CompletenessEntries = if ($Nhi.Completeness -is [System.Collections.IDictionary]) {
        @(foreach ($Key in $Nhi.Completeness.Keys) { @{ Name = [string]$Key; Value = $Nhi.Completeness[$Key] } })
    } elseif ($Nhi.Completeness) {
        @(foreach ($Property in $Nhi.Completeness.PSObject.Properties) { @{ Name = $Property.Name; Value = $Property.Value } })
    } else { @() }
    $CompletenessEntries = @($CompletenessEntries.Where({ $_.Value -and $_.Name -ne 'OtherTenants' }))
    $Skipped = @($CompletenessEntries.Where({ $_.Value.Skipped }))
    $Partial = @($CompletenessEntries.Where({ $_.Value.Complete -eq $false -and -not $_.Value.Skipped }))

    $Encode = [System.Net.WebUtility]
    $Variables = @{
        coverlabel         = 'Security Incident Report'
        covertitle         = 'App Compromise'
        coveraccent        = if ($IsSummary) { 'Summary' } else { 'Analysis' }
        covertenant        = $AppName
        coversubtitle      = "$(if ($IsSummary) { 'Executive summary of the non-human identity investigation' } else { 'Non-Human Identity Investigation Report' }) for $TenantName"
        covermeta          = if ($IsManagedIdentity) { "Managed identity $($Nhi.AppId)" } else { "Application ID $($Nhi.AppId)" }
        covermetanote      = "Analysis Date: $(& $FormatDate $Nhi.ExtractedAt)"
        coverfallbackimage = '/reportImages/soc.jpg'
        coverfooternote    = 'Confidential & Proprietary - For Internal Use Only'
        footerlabel        = "$TenantName - App Compromise $(if ($IsSummary) { 'Summary' } else { 'Report' }) for $AppName"
    }
    $b = [System.Collections.Generic.List[object]]::new()

    # === EXECUTIVE SUMMARY ===
    $b.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'Overview of the non-human identity compromise investigation'))
    $b.Add((New-CippReportParagraph -Html ('<p>This report documents a compromise investigation of the {0} <b>{1}</b> in <b>{2}</b>. It covers the {3} days up to {4}, compared with the {5} days before: the {0}''s credentials, sign-ins, the changes made to it, what it changed in the directory, and the mail and files it reached.</p>' -f $Kind, $Encode::HtmlEncode($AppName), $Encode::HtmlEncode([string]$TenantName), $WindowDays, $Encode::HtmlEncode((& $FormatDate $Nhi.EndDate)), $BaselineDays)))
    $b.Add((New-CippReportParagraph -Text 'Apps and managed identities sign in on their own, with a secret, a certificate or a federated credential, and act with the permissions they were given. An attacker holding one of those credentials acts as the app: no MFA prompt stops them, and resetting a user''s password does not remove their access.'))

    $b.Add((New-CippReportHeading -Title 'Investigation Overview'))
    $b.Add((New-CippReportStatRow -Stats @(
                @{ value = "$([int]$Nhi.SignInSummary.Total)"; label = 'Sign-ins in Window' }
                @{ value = "$($AttackerIPs.Count)"; label = 'Attacker Addresses' }
                @{ value = "$($FlaggedCredentials.Count + $UntrustedFederated.Count)"; label = 'Flagged Credentials' }
                @{ value = "$($HighElevations.Count + $PersistenceInWindow.Count)"; label = 'Access Granted or Persistence' }
            )))
    $LevelText = switch ($Level) {
        'Critical' { "CRITICAL: Strong evidence of compromise against $AKind with wide access. Contain it now: an attacker holding it can act across the tenant." }
        'High' { "HIGH RISK: Evidence points to $AKind that is compromised. Immediate containment is strongly recommended." }
        'Medium' { "MEDIUM RISK: Suspicious activity was found. Review the findings and contain the $Kind if they are not explained by a planned change." }
        default { "LOW RISK: No significant indicator of compromise was found. Continue monitoring as a precaution." }
    }
    $b.Add((New-CippReportAlertBox -Colour $LevelColour -Title "Case Level: $Level" -Content "$LevelText The level crosses the evidence ($([string]$Score.EvidenceLevel), score $([int]$Score.Value)) with what the $Kind's access reaches ($([string]$Score.Impact) impact$(if ($Score.PSObject.Properties['ImpactKnown'] -and -not $Score.ImpactKnown) { ', unknown: rated Medium' }))."))
    if ($Applied.Count -gt 0) {
        $b.Add((New-CippReportInfoBox -Lines -Title 'Signals that contributed to the score' -Content ((@($Applied | ForEach-Object { "+$([int]$_.Weight) $($_.Description)$(if ([int]$_.Count -gt 1) { " ($([int]$_.Count))" })" })) -join "`n")))
    }
    if ($Exposure) {
        $b.Add((New-CippReportInfoBox -Title "What the $KindTitle Can Reach" -Content ("Exposure: $(if ($Exposure.Risk) { $Exposure.Risk } else { 'Unknown' }) risk, highest impact $(if ($Exposure.HighestImpact) { $Exposure.HighestImpact } else { 'Low' }), across $([int]$Exposure.PermissionCount) catalogued permission(s) and role(s). Whoever controls the $Kind holds this access.")))
    }

    $b.Add((New-CippReportHeading -Title 'What We Found'))
    if ($Found.Count -gt 0) {
        $b.Add((New-CippReportParagraph -Html ('<p>In plain terms, this is what the investigation established about <b>{0}</b>:</p>' -f $Encode::HtmlEncode($AppName))))
        $b.Add((New-CippReportBullets -Items @($Found | ForEach-Object { @{ text = $_ } })))
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No indicators of compromise' -Content "None of the investigation's checks returned evidence that the $Kind was misused, or its credentials or access changed, during the window."))
    }

    $b.Add((New-CippReportHeading -Title 'Findings at a Glance'))
    $b.Add((New-CippReportParagraph -Text "Every check in this investigation and its result. $(if (-not $IsSummary) { 'Flagged rows are expanded in the detailed findings later in this report. ' })$FlaggedAreas of $($SummaryRows.Count) checks returned something to review."))
    $b.Add((New-CippReportTable -Columns @(
                @{ header = 'Check'; key = 'area'; width = 3; bold = $true }
                @{ header = 'Result'; key = 'result'; width = 2; toneField = 'tone' }
            ) -Rows $SummaryRows -Limit $SummaryRows.Count))
    if (-not $IsSummary) {
        $b.Add((New-CippReportNote -Text 'Checks that could not run (a missing licence or permission) are listed under Data Source Information below: a check that did not run is not a pass.'))
    }

    $b.Add((New-CippReportHeading -Title 'Priority Remediation Actions'))
    $b.Add((New-CippReportParagraph -Text 'Actions specific to what this investigation found, most urgent first. Disabling the app, removing credentials, owners, permissions and roles, and disabling the apps it took over can all be run from the case in CIPP.'))
    $b.Add((New-CippReportTable -Columns @(
                @{ header = 'Priority'; key = 'tag'; width = 1; toneField = 'tone' }
                @{ header = 'Action'; key = 'text'; width = 5 }
            ) -Rows $PriorityRows -Limit $PriorityRows.Count))

    $b.Add((New-CippReportHeading -Title 'Order of Events'))
    if ($TimelineRows.Count -gt 0) {
        $b.Add((New-CippReportParagraph -Text "The dated signals of the window in the order they happened: changes made to the $Kind, what it changed in the directory, sign-ins from attacker addresses, risk detections, consents and inbox rules."))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Event'; key = 'event'; width = 3 }
                    @{ header = 'Detail'; key = 'detail'; width = 3 }
                ) -Rows $TimelineRows -Limit $TimelineLimit))
        if ($SortedEvents.Count -gt $TimelineLimit) {
            $b.Add((New-CippReportNote -Text "The first $TimelineLimit of $($SortedEvents.Count) events are shown; the case's evidence export has them all."))
        }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No flagged events in the window' -Content "None of the checks returned a flagged, dated event inside the window: no flagged change to the $Kind, nothing it changed in the directory and no sign-in from an attacker address."))
    }

    # The summary stops after the executive lead: completed actions are marked in the priority table instead
    if ($IsSummary) { return @{ Blocks = @($b); Variables = $Variables } }

    if ($RemediationRows.Count -gt 0) {
        $b.Add((New-CippReportHeading -Title 'Remediation Taken'))
        $b.Add((New-CippReportParagraph -Text 'The containment already run from this case, and its result for each target.'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Action'; key = 'action'; width = 2 }
                    @{ header = 'Target'; key = 'target'; width = 2 }
                    @{ header = 'Result'; key = 'result'; width = 3 }
                    @{ header = 'State'; key = 'state'; width = 1; toneField = 'tone' }
                ) -Rows $RemediationRows -Limit $RemediationRows.Count))
    }

    $b.Add((New-CippReportHeading -Title 'Data Source Information'))
    $b.Add((New-CippReportInfoBox -Title 'Analysis Period' -Content ("$WindowDays days ending $(& $FormatDate $Nhi.EndDate), compared with the $BaselineDays days before")))
    if ($Nhi.CaseId) {
        $b.Add((New-CippReportInfoBox -Title 'Case' -Content "$($Nhi.CaseId). Metadata only: sign-ins, audit records, credentials, permissions and owners were collected; no message or file content was read."))
    }
    if ($Skipped.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($Skipped.Count) check(s) could not run" -Content ((@($Skipped | ForEach-Object { "$($_.Name): $(if ($_.Value.Requirement) { $_.Value.Requirement } else { 'not checked' })" })) -join "`n")))
    }
    if ($Partial.Count -gt 0) {
        $b.Add((New-CippReportAlertBox -Lines -Title "[!] $($Partial.Count) check(s) returned partial data" -Content ((@($Partial | ForEach-Object { "$($_.Name): $(if ($_.Value.Error) { $_.Value.Error } else { "capped at $($_.Value.Cap)" })" })) -join "`n")))
    }

    # === ADDRESSES ===
    $b.Add((New-CippReportPage -Title 'Sign-in Addresses' -Subtitle "Where the $Kind signed in and acted from"))
    $b.Add((New-CippReportParagraph -Text "Every address the $Kind signed in or acted from was judged against the addresses, networks and countries it used in the $BaselineDays days before the window, the credentials used from it, and the IP allow and block lists. Addresses judged the attacker's drive the findings; suspicious ones are listed for review only."))
    if ($ReviewIPs.Count -gt 0) {
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'Address'; key = 'ip'; width = 2; bold = $true }
                    @{ header = 'Verdict'; key = 'verdict'; width = 2; toneField = 'tone' }
                    @{ header = 'Location'; key = 'location'; width = 2 }
                    @{ header = 'Sign-ins'; key = 'signIns'; width = 1 }
                    @{ header = 'Why'; key = 'why'; width = 4 }
                ) -Rows @(foreach ($Verdict in @($ReviewIPs | Select-Object -First 15)) {
                    $Place = (@($Verdict.City, $Verdict.Country, $Verdict.ASName) | Where-Object { $_ }) -join ', '
                    @{
                        ip       = [string]$Verdict.IP
                        verdict  = ([string]$Verdict.Verdict -creplace '([a-z])([A-Z])', '$1 $2')
                        tone     = if ($Verdict.Verdict -in $AttackerVerdicts) { 'fail' } else { 'warn' }
                        location = if ($Place) { $Place } else { 'Unknown' }
                        signIns  = "$([int]$Verdict.SuccessfulSignIns) ok / $([int]$Verdict.FailedSignIns) failed"
                        why      = (@($Verdict.Reasons | Where-Object { [int]$_.Weight -gt 0 } | Sort-Object -Property { [int]$_.Weight } -Descending -Stable | Select-Object -First 3 | ForEach-Object { $_.Text })) -join '; '
                    }
                }) -Limit 15))
        if ($ReviewIPs.Count -gt 15) { $b.Add((New-CippReportNote -Text "The first 15 of $($ReviewIPs.Count) addresses are shown; the case's evidence export has them all.")) }
    } elseif ($Verdicts.Count -eq 0) {
        $b.Add((New-CippReportParagraph -Text "No sign-in or activity address was collected for the $Kind in the window. If the sign-in check could not run, it is listed under Data Source Information."))
    } else {
        $b.Add((New-CippReportClearBox -Title "[Pass] No address was judged the attacker's" -Content "None of the $($Verdicts.Count) address(es) the $Kind used was judged to be an attacker's or suspicious."))
    }

    # === CREDENTIALS ===
    $b.Add((New-CippReportPage -Title 'Credentials' -Subtitle "The secrets, certificates and federated credentials the $Kind signs in with"))
    if ($IsManagedIdentity) {
        $b.Add((New-CippReportParagraph -Text 'Azure manages the credentials of a managed identity; any secret or certificate listed here was added to it by hand.'))
    }
    $b.Add((New-CippReportParagraph -Text 'A credential is flagged when it was added in the window, added by another app, given a start date before it was added, or trusts an identity provider CIPP does not recognise. A credential that replaced an expiring one is a rotation, not a finding.'))
    if ($Credentials.Count -gt 0) {
        $OrderedCredentials = @(@($Credentials.Where({ $_.KeyId -and $FlaggedKeys.Contains([string]$_.KeyId) })) + @($Credentials.Where({ -not ($_.KeyId -and $FlaggedKeys.Contains([string]$_.KeyId)) })))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'Credential'; key = 'name'; width = 3; bold = $true }
                    @{ header = 'Type'; key = 'type'; width = 1 }
                    @{ header = 'Added'; key = 'added'; width = 3 }
                    @{ header = 'Expires'; key = 'expires'; width = 2 }
                    @{ header = 'Last sign-in'; key = 'lastSignIn'; width = 2 }
                    @{ header = 'Flags'; key = 'flags'; width = 2; toneField = 'tone' }
                ) -Rows @(foreach ($Credential in @($OrderedCredentials | Select-Object -First 20)) {
                    $IsFlagged = $Credential.KeyId -and $FlaggedKeys.Contains([string]$Credential.KeyId)
                    $Flags = @(foreach ($Flag in @($Credential.Flags | Where-Object { $_ })) { if ($FlagLabels[[string]$Flag]) { $FlagLabels[[string]$Flag] } else { [string]$Flag } }) -join ', '
                    @{
                        name       = "$(if ($Credential.DisplayName) { $Credential.DisplayName } else { $Credential.KeyId }) ($($Credential.Location))"
                        type       = [string]$Credential.Type
                        added      = (@((& $FormatDate $Credential.AddedDateTime), $(if ($Credential.AddedBy) { "by $($Credential.AddedBy)" })) | Where-Object { $_ }) -join ' '
                        expires    = if ($Credential.Expired) { 'Expired' } elseif ($Credential.EndDateTime) { & $FormatDate $Credential.EndDateTime } else { '-' }
                        lastSignIn = if ($Credential.LastSignInDateTime) { & $FormatDate $Credential.LastSignInDateTime } else { '-' }
                        flags      = if ($IsFlagged -and -not $Flags) { 'flagged' } elseif ($Flags) { $Flags } else { '-' }
                        tone       = if ($IsFlagged -or @($Credential.Flags) -contains 'UntrustedIssuer') { 'fail' } else { '' }
                    }
                }) -Limit 20))
        if ($Credentials.Count -gt 20) { $b.Add((New-CippReportNote -Text "The first 20 of $($Credentials.Count) credentials are shown, flagged ones first.")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No credentials' -Content "The $Kind holds no secret, certificate or federated credential CIPP can see."))
    }
    $ByCredential = @($Nhi.SignInsByCredential | Where-Object { $_ })
    if ($ByCredential.Count -gt 0) {
        $CredentialNames = @{}
        foreach ($Credential in $Credentials) { if ($Credential.KeyId -and $Credential.DisplayName) { $CredentialNames[[string]$Credential.KeyId] = [string]$Credential.DisplayName } }
        $b.Add((New-CippReportHeading -Title 'Sign-ins by Credential'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'Credential'; key = 'key'; width = 3; bold = $true }
                    @{ header = 'Type'; key = 'type'; width = 2 }
                    @{ header = 'Sign-ins'; key = 'count'; width = 2; toneField = 'tone' }
                    @{ header = 'Last'; key = 'last'; width = 2 }
                    @{ header = 'Addresses'; key = 'ips'; width = 3 }
                ) -Rows @(foreach ($Row in @($ByCredential | Sort-Object -Property { [int]$_.Count } -Descending | Select-Object -First 15)) {
                    $IsFlagged = $Row.KeyId -and $FlaggedKeys.Contains([string]$Row.KeyId)
                    @{
                        key   = "$(if ($CredentialNames[[string]$Row.KeyId]) { $CredentialNames[[string]$Row.KeyId] } elseif ($Row.KeyId) { $Row.KeyId } else { 'Unknown' })$(if ($IsFlagged) { ' (flagged)' })"
                        type  = [string]$Row.CredentialType
                        count = "$([int]$Row.Success) ok / $([int]$Row.Failed) failed"
                        tone  = if ($IsFlagged -and [int]$Row.Success -gt 0) { 'fail' } else { '' }
                        last  = & $FormatDate $Row.Last
                        ips   = & $ListNames @($Row.IPs)
                    }
                }) -Limit 15))
    }

    # === CHANGES AND ACTIONS ===
    $b.Add((New-CippReportPage -Title 'Changes and Actions' -Subtitle "Changes made to the $Kind, and what it did in the directory"))
    $b.Add((New-CippReportHeading -Title "Changes to the $KindTitle"))
    if ($FlaggedChanges.Count -gt 0) {
        $b.Add((New-CippReportParagraph -Text 'Changes in the window to what lets the app sign in or what it can reach: credentials, federated credentials, owners, redirect URIs, who may use it, and the access granted to it.'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Change'; key = 'activity'; width = 3 }
                    @{ header = 'By'; key = 'by'; width = 2 }
                    @{ header = 'Detail'; key = 'detail'; width = 3 }
                ) -Rows @(foreach ($Change in @($FlaggedChanges | Select-Object -First 20)) {
                    @{ when = & $FormatDate $Change.ActivityDateTime; activity = [string]$Change.Activity; by = "$($Change.InitiatedBy)$(if ($Change.ByApp) { ' (app)' })"; detail = [string]$Change.Detail }
                }) -Limit 20))
    } else {
        $b.Add((New-CippReportClearBox -Title "[Pass] No flagged change to the $Kind" -Content "Nothing that lets the $Kind sign in, or widens what it can reach, was changed in the window."))
    }
    if ($Elevations.Count -gt 0) {
        $b.Add((New-CippReportHeading -Title "Access the $KindTitle Granted"))
        $b.Add((New-CippReportParagraph -Text "Permissions and directory roles the $Kind gave itself, other apps or users, rated by what they allow. That access stays after the $Kind is disabled."))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Granted'; key = 'permission'; width = 3 }
                    @{ header = 'Impact'; key = 'impact'; width = 1; toneField = 'tone' }
                    @{ header = 'To'; key = 'recipient'; width = 3 }
                ) -Rows @(foreach ($Action in @(@($ElevationsInWindow) + @($Elevations.Where({ -not $_.InWindow })) | Select-Object -First 20)) {
                    @{
                        when       = "$(& $FormatDate $Action.ActivityDateTime)$(if (-not $Action.InWindow) { ' (before the window)' })"
                        permission = "$($Action.Permission)$(if ($Action.ElevationType) { " ($($Action.ElevationType))" })"
                        impact     = [string]$Action.Impact
                        tone       = if ($Action.Impact -in 'High', 'Critical') { 'fail' } elseif ($Action.Impact -eq 'Medium') { 'warn' } else { '' }
                        recipient  = if ($Action.Recipient -eq 'Self') { 'Itself' } else { "$(if ($Action.RecipientName) { $Action.RecipientName } else { $Action.RecipientId }) ($([string]$Action.Recipient))" }
                    }
                }) -Limit 20))
    }
    if ($Persistence.Count -gt 0) {
        $b.Add((New-CippReportHeading -Title 'Apps It Created or Took Over'))
        $b.Add((New-CippReportParagraph -Text "Apps the $Kind created, and credentials or owners it added to other apps. Each can keep access after this $Kind is disabled: investigate them too."))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Action'; key = 'activity'; width = 3 }
                    @{ header = 'App'; key = 'app'; width = 3 }
                    @{ header = 'Note'; key = 'note'; width = 2; toneField = 'tone' }
                ) -Rows @(foreach ($Action in @(@($PersistenceInWindow) + @($Persistence.Where({ -not $_.InWindow })) | Select-Object -First 15)) {
                    @{
                        when     = "$(& $FormatDate $Action.ActivityDateTime)$(if (-not $Action.InWindow) { ' (before the window)' })"
                        activity = [string]$Action.Activity
                        app      = [string]$Action.TargetDisplayName
                        note     = if ($Action.TargetProtected) { "Microsoft's or CIPP's app" } elseif ($Action.CreatedApp) { 'Created' } else { 'Taken over' }
                        tone     = if ($Action.InWindow) { 'fail' } else { 'warn' }
                    }
                }) -Limit 15))
    }
    if ($OtherActions.Count -gt 0) {
        $b.Add((New-CippReportHeading -Title 'Other Directory Changes'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                    @{ header = 'Activity'; key = 'activity'; width = 3 }
                    @{ header = 'Severity'; key = 'severity'; width = 1; toneField = 'tone' }
                    @{ header = 'Targets'; key = 'targets'; width = 3 }
                ) -Rows @(foreach ($Action in @($OtherActions | Select-Object -First 20)) {
                    @{
                        when     = & $FormatDate $Action.ActivityDateTime
                        activity = [string]$Action.Activity
                        severity = [string]$Action.Severity
                        tone     = if ($Action.Severity -eq 'Critical') { 'fail' } else { 'warn' }
                        targets  = & $ListNames @($Action.Targets | ForEach-Object { if ($_.UserPrincipalName) { $_.UserPrincipalName } else { $_.DisplayName } })
                    }
                }) -Limit 20))
        if ($OtherActions.Count -gt 20) { $b.Add((New-CippReportNote -Text "The first 20 of $($OtherActions.Count) changes are shown; the case's evidence export has them all.")) }
    }

    # === MAIL AND FILES ===
    $Mailboxes = @($WorkloadActivity.Mailboxes | Where-Object { $_ })
    $Sites = @($WorkloadActivity.Sites | Where-Object { $_ })
    $Rules = @($WorkloadActivity.InboxRules | Where-Object { $_ })
    if ($Mailboxes.Count -or $Sites.Count -or $Rules.Count) {
        $b.Add((New-CippReportPage -Title 'Mail and Files' -Subtitle "What the $Kind reached in Exchange Online, SharePoint and OneDrive"))
        $b.Add((New-CippReportStatRow -Stats @(
                    @{ value = "$([int]$Workload.MailboxCount)"; label = 'Mailboxes' }
                    @{ value = "$([int]$Workload.MailItemCount)"; label = 'Mail Items Accessed' }
                    @{ value = "$([int]$Workload.SendCount)"; label = 'Messages Sent' }
                    @{ value = "$([int]$Workload.FileCount)"; label = 'Files' }
                )))
        $Baseline = $Nhi.WorkloadBaseline
        $b.Add((New-CippReportParagraph -Text ("From the unified audit log. $(if ($Baseline) { "In the $BaselineDays days before the window the $Kind reached $(@($Baseline.Mailboxes).Count) mailbox(es) and $(@($Baseline.Sites).Count) site(s); only reach beyond those counts as mass access." } else { 'What it reached before the window could not be read, so all of it counts.' }) Only the mailboxes and sites are listed: no message or file content was read.")))
        if ($Mailboxes.Count) {
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'Mailbox'; key = 'mailbox'; width = 3; bold = $true }
                        @{ header = 'Operations'; key = 'count'; width = 1 }
                        @{ header = 'What'; key = 'operations'; width = 3 }
                        @{ header = 'Last'; key = 'last'; width = 2 }
                    ) -Rows @(foreach ($Mailbox in @($Mailboxes | Select-Object -First 15)) {
                        @{ mailbox = [string]$Mailbox.Mailbox; count = "$([int]$Mailbox.Count)"; operations = (@($Mailbox.Operations) -join ', '); last = & $FormatDate $Mailbox.Last }
                    }) -Limit 15))
            if ($Mailboxes.Count -gt 15) { $b.Add((New-CippReportNote -Text "The 15 busiest of $($Mailboxes.Count) mailboxes are shown.")) }
        }
        if ($Sites.Count) {
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'Site'; key = 'site'; width = 4; bold = $true }
                        @{ header = 'Files'; key = 'files'; width = 1 }
                        @{ header = 'What'; key = 'operations'; width = 3 }
                    ) -Rows @(foreach ($Site in @($Sites | Select-Object -First 10)) {
                        # the site, never the file: a record without a site URL carries the file's own URL
                        $SiteUrl = [string]$Site.Site
                        $SiteMatch = [regex]::Match($SiteUrl, '^https?://[^/]+(/(sites|teams|personal)/[^/]+)?', 'IgnoreCase')
                        @{ site = if ($SiteMatch.Success) { $SiteMatch.Value } else { $SiteUrl }; files = "$([int]$Site.FileCount)"; operations = (@($Site.Operations) -join ', ') }
                    }) -Limit 10))
        }
        if ($Rules.Count) {
            $b.Add((New-CippReportHeading -Title 'Inbox Rules'))
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                        @{ header = 'Operation'; key = 'operation'; width = 2 }
                        @{ header = 'Mailbox'; key = 'mailbox'; width = 3 }
                        @{ header = 'Address'; key = 'ip'; width = 2 }
                    ) -Rows @(foreach ($Rule in @($Rules | Select-Object -First 10)) {
                        @{ when = & $FormatDate $Rule.CreationTime; operation = [string]$Rule.Operation; mailbox = [string]$Rule.Mailbox; ip = [string]$Rule.ClientIP }
                    }) -Limit 10))
        }
    }

    # === ACCESS AND OWNERS ===
    $b.Add((New-CippReportPage -Title 'Access and Owners' -Subtitle "What a compromise of the $Kind reaches, and who can add a credential to it"))
    $b.Add((New-CippReportInfoBox -Lines -Title "About the $KindTitle" -Content ((@(
                    "Name: $AppName"
                    "Application ID: $($Nhi.AppId)"
                    "Type: $(if ($IsManagedIdentity) { 'Managed identity' } elseif ($Subject.Ownership) { $Subject.Ownership } else { 'App' })"
                    $(if ($Subject.VerifiedPublisher) { "Verified publisher: $($Subject.VerifiedPublisher)" } elseif ($Subject.PublisherName) { "Publisher: $($Subject.PublisherName) (not verified)" })
                    $(if ($Subject.CreatedDateTime) { "Added to the tenant: $(& $FormatDate $Subject.CreatedDateTime)" })
                    "Enabled: $(if ($Subject.AccountEnabled -eq $false) { 'No' } else { 'Yes' })"
                    $(if ($Subject.AzureResourceId) { "Azure resource: $($Subject.AzureResourceId)" })
                ) | Where-Object { $_ }) -join "`n")))
    $RiskReasons = @($Exposure.RiskReasons | Where-Object { $_ })
    if ($RiskReasons.Count) {
        $b.Add((New-CippReportBullets -Title 'Why the access is rated this way' -Items @($RiskReasons | ForEach-Object { @{ text = [string]$_ } })))
    }
    $ImpactRank = @{ Critical = 4; High = 3; Medium = 2; Low = 1 }
    $Permissions = @($Exposure.PermissionDetails | Where-Object { $_ } | Sort-Object -Property { [int]$ImpactRank[[string]$_.Impact] } -Descending -Stable)
    if ($Permissions.Count) {
        $b.Add((New-CippReportHeading -Title 'Highest-Impact Access'))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'Permission or role'; key = 'name'; width = 3; bold = $true }
                    @{ header = 'Type'; key = 'type'; width = 2 }
                    @{ header = 'Impact'; key = 'impact'; width = 1; toneField = 'tone' }
                    @{ header = 'What it allows'; key = 'reason'; width = 4 }
                ) -Rows @(foreach ($Permission in @($Permissions | Select-Object -First 15)) {
                    @{
                        name   = (@($Permission.Api, $Permission.Name) | Where-Object { $_ }) -join ' '
                        type   = ([string]$Permission.Type -creplace '([a-z])([A-Z])', '$1 $2')
                        impact = [string]$Permission.Impact
                        tone   = if ($Permission.Impact -in 'High', 'Critical') { 'fail' } elseif ($Permission.Impact -eq 'Medium') { 'warn' } else { '' }
                        reason = [string]$Permission.Reason
                    }
                }) -Limit 15))
        if ($Permissions.Count -gt 15) { $b.Add((New-CippReportNote -Text "The 15 highest-impact of $($Permissions.Count) permissions and roles are shown.")) }
    }
    $Owners = @($Nhi.Owners | Where-Object { $_ })
    $b.Add((New-CippReportHeading -Title 'Owners'))
    if ($Owners.Count) {
        $b.Add((New-CippReportParagraph -Text "Every owner can add a credential to the $Kind and act with its access."))
        $b.Add((New-CippReportTable -Columns @(
                    @{ header = 'Owner'; key = 'owner'; width = 3; bold = $true }
                    @{ header = 'Kind'; key = 'kind'; width = 1 }
                    @{ header = 'Owner of'; key = 'of'; width = 2 }
                ) -Rows @(foreach ($Owner in @($Owners | Select-Object -First 15)) {
                    @{ owner = if ($Owner.UserPrincipalName) { [string]$Owner.UserPrincipalName } else { [string]$Owner.DisplayName }; kind = if ($Owner.IsApp) { 'App' } elseif ($Owner.UserType) { [string]$Owner.UserType } else { 'User' }; of = [string]$Owner.OwnerOf }
                }) -Limit 15))
    } else {
        $b.Add((New-CippReportParagraph -Text "The $Kind has no owners in this tenant."))
    }

    # === USERS SIGNING IN ===
    $Delegated = @($Nhi.DelegatedSignIns | Where-Object { $_ })
    if ($Delegated.Count -or $ConsentsInWindow.Count) {
        $b.Add((New-CippReportPage -Title 'Users Signing In' -Subtitle 'The people who signed in to the app, and consents given to it'))
        $b.Add((New-CippReportParagraph -Text 'An app used for consent phishing shows as a burst of new users consenting; an app abusing their access shows as sign-ins on their behalf from its own servers.'))
        if ($Delegated.Count) {
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'User'; key = 'user'; width = 3; bold = $true }
                        @{ header = 'Sign-ins'; key = 'signIns'; width = 2 }
                        @{ header = 'Countries'; key = 'countries'; width = 2 }
                        @{ header = 'Last'; key = 'last'; width = 2 }
                    ) -Rows @(foreach ($User in @($Delegated | Select-Object -First 15)) {
                        @{ user = [string]$User.UserPrincipalName; signIns = "$([int]$User.SignIns) ($([int]$User.Successful) ok)"; countries = (@($User.Countries) -join ', '); last = & $FormatDate $User.Last }
                    }) -Limit 15))
            if ($Delegated.Count -gt 15) { $b.Add((New-CippReportNote -Text "The 15 most active of $($Delegated.Count) users are shown.")) }
        }
        if ($ConsentsInWindow.Count) {
            $b.Add((New-CippReportHeading -Title 'Consents in the Window'))
            $b.Add((New-CippReportTable -Columns @(
                        @{ header = 'When'; key = 'when'; width = 2; bold = $true }
                        @{ header = 'User'; key = 'user'; width = 3 }
                        @{ header = 'Address'; key = 'ip'; width = 2 }
                    ) -Rows @(foreach ($Consent in @($ConsentsInWindow | Select-Object -First 20)) {
                        @{ when = & $FormatDate $Consent.ActivityDateTime; user = [string]$Consent.User; ip = [string]$Consent.ClientIP }
                    }) -Limit 20))
        }
    }

    # === AUDIT TRAIL ===
    $b.Add((New-CippReportPage -Title 'Documentation' -Subtitle 'Audit trail and retention'))
    $b.Add((New-CippReportInfoBox -Lines -Title 'Investigation Details' -Content ((@(
                    "Investigation Date: $(& $FormatDate $Nhi.ExtractedAt)"
                    "Investigated $($Kind): $AppName"
                    "Application ID: $($Nhi.AppId)"
                    "Organization: $TenantName"
                    "Analysis Period: $WindowDays days, compared with the $BaselineDays days before"
                    "Case Level: $Level (evidence $([string]$Score.EvidenceLevel), score $([int]$Score.Value); impact $([string]$Score.Impact))"
                    $(if ($Nhi.CaseId) { "Case: $($Nhi.CaseId)" })
                ) | Where-Object { $_ }) -join "`n")))
    $b.Add((New-CippReportParagraph -Title 'Document Retention' -Text "This report should be retained according to your organization's document retention policy and regulatory requirements. Store it securely with restricted access: it contains sensitive security information."))

    @{
        Blocks    = @($b)
        Variables = $Variables
    }
}
