function Push-BECRun {
    <#
        .FUNCTIONALITY
        Entrypoint
        .SYNOPSIS
        Runs the Business Email Compromise check for one user and stores the run.
        .DESCRIPTION
        Queued by Invoke-ExecBECCheck / Invoke-ExecBECBulkCheck. Collects audit-log changes, sign-ins,
        rules, safelists, sharing, sent mail, apps, MFA, devices, the delegation inventory, the user's
        OAuth grants, transport rules, add-ins, received-mail heuristics, Defender detections, directory
        audits, registered devices, non-interactive sign-ins, mailbox-activity counts and Identity
        Protection state. Every collector records a completeness marker and the threat score is
        computed server-side. Results go to the BecReports table (metadata) and the BecResults table
        (payload), keyed by the case id. Metadata only - no message bodies, attachments or file contents.
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $SuspectUser = $Item.UserID
    $UserName = $Item.userName
    $CaseId = if ($Item.CaseId) { [string]$Item.CaseId } else { New-CIPPBecCaseId }

    if (!$TenantFilter -or !$SuspectUser) {
        Write-Information 'BEC: No user or tenant specified'
        return
    }

    # The collectors bind the UPN as a mandatory parameter and attribute audit records to it; a blank one
    # throws "empty string" across the run and makes the tenant-wide record filter (-UserIds / -like) match
    # everything, so unrelated tenant and admin actions surface as this user's compromise events. Resolve
    # it from the object id when the run was queued without one, and fail the run cleanly if it truly can't
    # be found rather than producing a run full of errors and false positives.
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        try {
            $ResolvedUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($SuspectUser)?`$select=userPrincipalName" -tenantid $TenantFilter -AsApp $true
            $UserName = [string]$ResolvedUser.userPrincipalName
            if (-not [string]::IsNullOrWhiteSpace($UserName)) {
                $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ UserPrincipalName = $UserName }
            }
        } catch {
            Write-Information "BEC: could not resolve a UPN for $SuspectUser in $TenantFilter`: $($_.Exception.Message)"
        }
    }
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        Write-Information "BEC: the investigated user ($SuspectUser) has no resolvable UPN; marking the run failed."
        try {
            $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Status = 'Error'; ErrorMessage = 'The investigated user could not be resolved to a user principal name (the account was deleted, or no UPN was provided to the run).'; ExtractedAt = (Get-Date).ToUniversalTime().ToString('o') }
        } catch {
            Write-Information "BEC: could not mark the unresolved run $CaseId failed: $($_.Exception.Message)"
        }
        return
    }

    Set-CippBecCaseContext -CaseId $CaseId
    Write-Information "Working on $UserName (case $CaseId)"

    # Live progress for the page: the async-deployment row keyed on the case id (created when the
    # run was queued; created here for runs queued another way), one step per phase. Progress
    # writes are best-effort - a failure to report never fails the run.
    $StepIndex = @{}
    $RunSteps = @(Get-CIPPBecRunSteps)
    for ($i = 0; $i -lt $RunSteps.Count; $i++) { $StepIndex[$RunSteps[$i].Key] = $i }
    $ProgressName = [string]$UserName
    $Progress = @{ Current = $null }
    try {
        # (Re)create the job so every step starts pending: Craft retries a killed activity under the same
        # case id, and the retry must not inherit the dead attempt's half-finished steps.
        $null = New-CIPPAsyncDeployment -JobId $CaseId -Names @($ProgressName) -StepTitles @($RunSteps.Title) -Source 'BEC' -TenantFilter $TenantFilter
        Set-CIPPAsyncDeploymentStatus -JobId $CaseId -Name $ProgressName -Status 'running'
        $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Status = 'Running'; StartedAt = (Get-Date).ToUniversalTime().ToString('o') }
    } catch {
        Write-Information "BEC: progress reporting unavailable for $CaseId`: $($_.Exception.Message)"
    }
    $Step = {
        param($Key, $Status, $Message)
        if (-not $StepIndex.ContainsKey($Key)) { return }
        Set-CIPPAsyncDeploymentStep -JobId $CaseId -Name $ProgressName -StepIndex $StepIndex[$Key] -StepStatus $Status -Message ([string]$Message)
    }
    # Marks the previous phase done and the next one running.
    $Phase = {
        param($Key, $Message)
        if ($Progress.Current) { & $Step $Progress.Current 'succeeded' 'Done' }
        $Progress.Current = $Key
        & $Step $Key 'running' $Message
    }
    try {
        $Heuristics = Get-CIPPBecHeuristics
        $Caps = $Heuristics.caps
        $WindowDays = [int]($Heuristics.window.days ?? 7)
        $startDate = (Get-Date).ToUniversalTime().AddDays(-$WindowDays)
        $endDate = (Get-Date).ToUniversalTime()
        $AuditPages = [int]($Caps.auditLogPages ?? 10)

        # Completeness marker per collector: { Complete, Cap, Error, Skipped, Requirement, Count }.
        # Skipped/Requirement are null-safe: inline markers that omit them read as $false/$null.
        $Completeness = [ordered]@{}
        $Mark = {
            param($Name, $Result)
            # Clean and classify the error once, here, so every collector benefits: known-benign
            # conditions (no mailbox, no Intune) become a skip with a plain reason, and raw Exchange
            # exception text is trimmed for display.
            $Info = if ($Result.Error) { Get-CIPPBecErrorInfo -Message ([string]$Result.Error) } else { $null }
            $Completeness[$Name] = [pscustomobject]@{
                Complete    = [bool]$Result.Complete
                Cap         = $Result.Cap
                Error       = if ($Info) { $Info.Message } else { $Result.Error }
                Skipped     = [bool]($Result.Skipped -or ($Info -and $Info.Skipped))
                Requirement = if ($Result.Requirement) { $Result.Requirement } elseif ($Info) { $Info.Requirement } else { $null }
                Count       = [int]$Result.Count
            }
        }

        # conditionalAccessStatus is 'success'/'notApplied'/'failure'; errorCode 0 is a successful
        # sign-in. Shared by every sign-in projection below.
        $SignInStatus = { if ($_.conditionalAccessStatus -in @('success', 'notApplied') -and $_.status.errorCode -eq 0) { 'Success' } else { 'Failed' } }
        # ISO 8601 so the frontend table formatter and new Date() can both parse it - Out-String
        # renders a locale string neither understands
        $SignInDate = { if ($_.createdDateTime) { ([datetime]$_.createdDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null } }

        # Licence preflight, up front and all at once: a check the tenant cannot support is skipped with
        # its reason instead of run only to fail. Get-CIPPTenantCapabilities is CIPP's shared (cached)
        # service-plan read and the plan names are the ones Test-CIPPStandardLicense's presets use. If
        # the read itself fails every check runs and the error classifier (Get-CIPPBecErrorInfo, via
        # $Mark) is the safety net - never skip on a failed preflight.
        $Capabilities = $null
        try {
            $Capabilities = Get-CIPPTenantCapabilities -TenantFilter $TenantFilter
        } catch {
            Write-LogMessage -API 'BECRun' -message "BEC preflight could not read tenant plans for $($TenantFilter): $((Get-NormalizedError -message $_.Exception.Message))" -tenant $TenantFilter -sev Info
        }
        $HasPlan = { param([string[]]$Plans) (-not $Capabilities) -or [bool]@($Plans | Where-Object { $Capabilities.$_ -eq $true }).Count }
        $HasEntraP2 = & $HasPlan 'AAD_PREMIUM_P2'
        $HasDefenderP2 = & $HasPlan 'THREAT_INTELLIGENCE', 'THREAT_INTELLIGENCE_GOV'
        $HasIntune = & $HasPlan 'INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1'
        $Skip = { param($Requirement) New-CIPPBecCollectorResult -Data @() -Skipped $true -Requirement $Requirement }

        & $Phase 'AuditLog' "Searching the unified audit log for the last $WindowDays days"
        Write-Information 'Getting audit logs'
        $auditLog = $null
        try {
            $auditLog = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AdminAuditLogConfig').UnifiedAuditLogIngestionEnabled
            if ($auditLog -eq $false) {
                $PermissionRecords = @()
                $ExtractResult = 'AuditLog is disabled. Cannot perform full analysis'
                & $Mark 'AuditLog' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = 'Unified audit log ingestion is disabled for this tenant'; Count = 0 })
            } else {
                $PermissionSearch = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $startDate -EndDate $endDate -Operations @('Remove-MailboxPermission', 'Add-MailboxPermission', 'UpdateCalendarDelegation', 'AddFolderPermissions') -Anchor $UserName -MaxPages $AuditPages
                $PermissionRecords = @($PermissionSearch.Records)
                Write-Information "Retrieved $($PermissionRecords.Count) permission change records"
                $ExtractResult = 'Successfully extracted logs from auditlog'
                & $Mark 'AuditLog' ([pscustomobject]@{ Complete = $PermissionSearch.Complete; Cap = $PermissionSearch.Cap; Error = $null; Count = $PermissionRecords.Count })
            }
        } catch {
            $PermissionRecords = @()
            $CippAuditError = Get-CippException -Exception $_
            $ExtractResult = "Could not retrieve audit logs: $($CippAuditError.NormalizedError)"
            & $Mark 'AuditLog' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $ExtractResult; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve audit logs for $($UserName): $($CippAuditError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippAuditError
        }
        & $Phase 'SignIns' 'Reading sign-ins and mobile devices'
        Write-Information 'Getting suspect user sign-ins'
        $SuspectUserSignInsError = $null
        try {
            # Every interactive sign-in in the window, paged to the end: the score's foreign sign-in
            # signals count these, so a newest-N cut would hide the first foreign access.
            $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$SuspectUser') and createdDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))&`$top=999&`$orderby=createdDateTime desc"
            $SuspectUserSignIns = @(New-GraphGetRequest -uri $URI -tenantid $TenantFilter | Select-Object @{ Name = 'CreatedDateTime'; Expression = $SignInDate },
                id,
                @{ Name = 'AppDisplayName'; Expression = { $_.resourceDisplayName } },
                @{ Name = 'ClientAppUsed'; Expression = { $_.clientAppUsed } },
                @{ Name = 'Status'; Expression = $SignInStatus },
                @{ Name = 'IPAddress'; Expression = { $_.ipAddress } },
                @{ Name = 'Country'; Expression = { $_.location.countryOrRegion } },
                @{ Name = 'City'; Expression = { $_.location.city } },
                # what the IP verdicts weigh: the network, Entra's own risk call, the client and device,
                # and the session/token ids that tie audited actions back to this sign-in
                @{ Name = 'ASN'; Expression = { $_.autonomousSystemNumber } },
                @{ Name = 'RiskLevelDuringSignIn'; Expression = { $_.riskLevelDuringSignIn } },
                @{ Name = 'RiskEventTypes'; Expression = { @($_.riskEventTypes_v2) } },
                @{ Name = 'UserAgent'; Expression = { $_.userAgent } },
                @{ Name = 'DeviceCompliant'; Expression = { $_.deviceDetail.isCompliant } },
                @{ Name = 'DeviceManaged'; Expression = { $_.deviceDetail.isManaged } },
                @{ Name = 'DeviceTrustType'; Expression = { $_.deviceDetail.trustType } },
                @{ Name = 'OperatingSystem'; Expression = { $_.deviceDetail.operatingSystem } },
                @{ Name = 'Browser'; Expression = { $_.deviceDetail.browser } },
                @{ Name = 'SessionId'; Expression = { $_.sessionId } },
                @{ Name = 'UniqueTokenId'; Expression = { $_.uniqueTokenIdentifier } },
                # the CIPP application's own sign-ins (its service account) are not the user's or an attacker's
                @{ Name = 'AppId'; Expression = { $_.appId } })
            & $Mark 'SignIns' ([pscustomobject]@{ Complete = $true; Cap = $null; Error = $null; Count = $SuspectUserSignIns.Count })
        } catch {
            $SuspectUserSignIns = @()
            $CippSignInError = Get-CippException -Exception $_
            $SuspectUserSignInsError = "Could not retrieve sign-in logs: $($CippSignInError.NormalizedError)"
            & $Mark 'SignIns' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $SuspectUserSignInsError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve sign-ins for $($UserName): $($CippSignInError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSignInError
        }
        Write-Information 'Getting user devices'
        #List all users devices
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($SuspectUser)
        $base64IdentityParam = [Convert]::ToBase64String($Bytes)
        try {
            $Devices = @(New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $TenantFilter -scope ExchangeOnline)
            & $Mark 'MobileDevices' ([pscustomobject]@{ Complete = $true; Cap = $null; Error = $null; Count = $Devices.Count })
        } catch {
            $Devices = @()
            & $Mark 'MobileDevices' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = "Could not retrieve mobile devices: $((Get-NormalizedError -message $_.Exception.Message))"; Count = 0 })
        }

        try {
            # for the target-mailbox heuristic below: canonical ObjectIds carry the alias, not the UPN
            $UserLocalPart = ($UserName -split '@')[0]
            $PermissionsLog = @($PermissionRecords | Where-Object { $_.AuditData -and $_.Operation -in 'Remove-MailboxPermission', 'Add-MailboxPermission', 'UpdateCalendarDelegation', 'AddFolderPermissions' } | ForEach-Object {
                    $AD = $_.AuditData
                    $perms = if ($AD.Parameters) {
                        $AD.Parameters | ForEach-Object { if ($_.Name -eq 'AccessRights') { $_.Value } }
                    } else
                    { $AD.item.ParentFolder.MemberRights }
                    $objectID = if ($AD.ObjectID) { $AD.ObjectID } else { $($AD.MailboxOwnerUPN) + $AD.item.ParentFolder.Path }
                    # this is a tenant-wide search; flag the rows that concern the investigated mailbox
                    # so the threat score can weight them above unrelated tenant churn
                    $IdentityParam = if ($AD.Parameters) { ($AD.Parameters | Where-Object { $_.Name -eq 'Identity' }).Value }
                    $TargetCandidates = @($objectID, $IdentityParam, $AD.MailboxOwnerUPN) -join ' '
                    # who received the access: the User/Trustee parameter, or the folder member for AddFolderPermissions
                    $Trustee = if ($AD.Parameters) { ($AD.Parameters | Where-Object { $_.Name -in @('User', 'Trustee', 'Delegate') } | Select-Object -First 1).Value } else { $AD.item.ParentFolder.MemberUpn ?? $AD.item.ParentFolder.MemberSid }
                    $TargetsSuspect = ($TargetCandidates -like "*$UserName*" -or ($UserLocalPart -and $TargetCandidates -like "*$UserLocalPart*"))
                    [pscustomobject]@{
                        Operation      = $AD.Operation
                        UserKey        = $AD.UserKey
                        UserId         = $AD.UserId
                        ObjectId       = $objectId
                        Permissions    = $perms
                        Trustee        = [string]$Trustee
                        Date           = $AD.CreationTime
                        ClientIP       = ConvertTo-CIPPBecHostAddress -Address ($AD.ClientIP ?? $AD.ClientIPAddress)
                        TargetsSuspect = $TargetsSuspect
                        # the full audit record, kept for the rows about this mailbox (the search is tenant-wide)
                        AuditData      = if ($TargetsSuspect) { $AD } else { $null }
                    }
                })
        } catch {
            $PermissionsLog = @()
        }

        & $Phase 'MailboxRules' 'Reading inbox rules, safelists and sharing links'

        # Inbox-rule, safelist and sharing changes are all user-scoped to the same mailbox and window;
        # only their operations differ, and the unified-audit-log session is the slow part. One combined
        # search feeds all three (partitioned by operation locally) instead of three separate sessions.
        $RuleOps = @('New-InboxRule', 'Set-InboxRule', 'Remove-InboxRule', 'UpdateInboxRules')
        $SafelistOps = @('Set-MailboxJunkEmailConfiguration')
        $SharingOps = @('SharingSet', 'SharingInvitationCreated', 'AnonymousLinkCreated', 'AnonymousLinkUpdated', 'SecureLinkCreated', 'SecureLinkUpdated', 'AddedToSecureLink', 'CompanyLinkCreated')
        $ChangeSearch = $null
        $ChangeSearchError = $null
        if ($auditLog -ne $false) {
            try {
                $ChangeSearch = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $startDate -EndDate $endDate -Operations @($RuleOps + $SafelistOps + $SharingOps) -UserIds @($UserName) -Anchor $UserName -MaxPages $AuditPages
            } catch {
                $ChangeSearchError = Get-CippException -Exception $_
            }
        }
        $ChangeRecords = @($ChangeSearch.Records)

        Write-Information 'Getting inbox rule changes'
        try {
            $RuleChangesLog = if ($auditLog -eq $false) { @() } else {
                if ($ChangeSearchError) { throw $ChangeSearchError.NormalizedError }
                $RuleRecords = @($ChangeRecords | Where-Object { $RuleOps -contains [string]$_.Operation })
                & $Mark 'InboxRuleChanges' ([pscustomobject]@{ Complete = [bool]$ChangeSearch.Complete; Cap = $ChangeSearch.Cap; Error = $null; Count = $RuleRecords.Count })
                @($RuleRecords | ForEach-Object { $_.AuditData } | Where-Object { $_ -and ($_.UserId -eq $UserName -or $_.MailboxOwnerUPN -eq $UserName -or $_.ObjectId -like "*$UserName*") } | ForEach-Object {
                        $RuleName = ($_.Parameters | Where-Object { $_.Name -eq 'Name' }).Value ?? $_.ObjectId
                        [pscustomobject]@{
                            Operation  = $_.Operation
                            UserKey    = $_.UserId
                            RuleName   = $RuleName
                            Parameters = ($_.Parameters | Where-Object { $_ -and $_.Name -notin 'Identity', 'Name' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
                            Date       = $_.CreationTime
                            # admin-cmdlet records carry ClientIP, mailbox-sync records (UpdateInboxRules) ClientIPAddress
                            ClientIP   = ConvertTo-CIPPBecHostAddress -Address ($_.ClientIP ?? $_.ClientIPAddress)
                            AuditData  = $_
                        }
                    })
            }
        } catch {
            $RuleChangesLog = @()
            $CippRuleError = Get-CippException -Exception $_
            & $Mark 'InboxRuleChanges' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $CippRuleError.NormalizedError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve inbox rule changes for $($UserName): $($CippRuleError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippRuleError
        }

        Write-Information 'Getting rules'

        try {
            $RulesLog = New-ExoRequest -cmdlet 'Get-InboxRule' -tenantid $TenantFilter -cmdParams @{ Mailbox = $Username; IncludeHidden = $true } -Anchor $Username |
                Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' }
            & $Mark 'InboxRules' ([pscustomobject]@{ Complete = $true; Cap = $null; Error = $null; Count = @($RulesLog | Where-Object { $_ }).Count })
        } catch {
            $CippRulesError = Get-CippException -Exception $_
            & $Mark 'InboxRules' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $CippRulesError.NormalizedError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve inbox rules for $($UserName): $($CippRulesError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippRulesError
            $RulesLog = @()
        }

        # inbox rules carry no timestamps, so 'recent' = name-matches an audit event in the window; Outlook-client changes (UpdateInboxRules) carry no rule name and stay unflagged
        $RecentRuleNames = @($RuleChangesLog | Where-Object { $_.Operation -in 'New-InboxRule', 'Set-InboxRule' } | ForEach-Object { ($_.RuleName -split '\\')[-1] })
        $LowVisibilityRegex = [string]$Heuristics.inboxRules.lowVisibilityFolderRegex
        $SensitiveNameRegex = [string]$Heuristics.inboxRules.sensitiveNameRegex
        $SensitiveKeywordRegex = [string]$Heuristics.inboxRules.sensitiveKeywordRegex
        $SuspiciousFolder = [string]$Heuristics.inboxRules.suspiciousFolderPattern
        # AcceptedDomains is fetched later, so 'external' here is any forward domain that is not the
        # user's own domain or the tenant's default domain - approximate, but the false positive
        # (a legitimate internal forward across a second accepted domain) is still worth a look.
        $InternalDomains = @(($UserName -split '@')[-1], $TenantFilter) | ForEach-Object { ([string]$_).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique
        # Condition properties that scope a rule to specific mail; with none set the rule acts on everything.
        $RuleConditionProps = @('From', 'FromAddressContainsWords', 'SubjectContainsWords', 'BodyContainsWords', 'SubjectOrBodyContainsWords', 'SentTo', 'RecipientAddressContainsWords', 'HeaderContainsWords', 'MyNameInToBox', 'MyNameInCcBox', 'MyNameInToOrCcBox', 'HasAttachment', 'MessageTypeMatches', 'WithImportance', 'WithSensitivity', 'FromSubscription', 'FlaggedForAction')
        # Condition properties whose words are scanned for financial/sensitive terms.
        $RuleKeywordProps = @('SubjectContainsWords', 'BodyContainsWords', 'SubjectOrBodyContainsWords', 'FromAddressContainsWords', 'HeaderContainsWords')
        $RulesLog = @($RulesLog | Where-Object { $_ } | ForEach-Object {
                $Rule = $_
                $Reasons = [System.Collections.Generic.List[string]]::new()
                # Forwarding/redirection - external is the exfiltration case, called out separately.
                $ForwardTargets = @(@($Rule.ForwardTo) + @($Rule.RedirectTo) + @($Rule.ForwardAsAttachmentTo) | Where-Object { $_ })
                $ForwardDomains = @($ForwardTargets | ForEach-Object { if ("$_" -match '@([A-Za-z0-9.\-]+)') { $Matches[1].ToLowerInvariant() } } | Where-Object { $_ })
                $ExternalForward = @($ForwardDomains | Where-Object { $InternalDomains -notcontains $_ }).Count -gt 0
                if ($ExternalForward) { $Reasons.Add('Forwards or redirects mail to an external address') }
                elseif ($ForwardTargets.Count -gt 0) { $Reasons.Add('Forwards or redirects messages') }
                if ($Rule.DeleteMessage -eq $true) { $Reasons.Add('Deletes messages') }
                if ($Rule.MarkAsRead -eq $true) { $Reasons.Add('Marks messages as read') }
                $MovesToLowVis = [bool]($LowVisibilityRegex -and [string]$Rule.MoveToFolder -match $LowVisibilityRegex)
                if ($MovesToLowVis) { $Reasons.Add('Moves messages to a low-visibility folder') }
                if ($Rule.StopProcessingRules -eq $true) { $Reasons.Add('Stops processing other rules') }
                $KeywordHit = $false
                if ($SensitiveKeywordRegex) { foreach ($KP in $RuleKeywordProps) { if ((@($Rule.$KP) -join ' ') -match $SensitiveKeywordRegex) { $KeywordHit = $true; break } } }
                if ($KeywordHit) { $Reasons.Add('Targets financial or sensitive keywords') }
                # Acts on all mail: a hiding/exfil action (forward, delete, move) with no scoping condition.
                $HasCondition = $false
                foreach ($CP in $RuleConditionProps) { $CV = $Rule.$CP; if (($CV -is [bool] -and $CV) -or (@($CV | Where-Object { $_ }).Count -gt 0)) { $HasCondition = $true; break } }
                $HidingAction = [bool]($ForwardTargets.Count -gt 0 -or ($Rule.DeleteMessage -eq $true) -or $Rule.MoveToFolder)
                $ActsOnAll = ($HidingAction -and -not $HasCondition)
                if ($ActsOnAll) { $Reasons.Add('Acts on all incoming mail') }
                if ($SensitiveNameRegex -and [string]$Rule.Name -match $SensitiveNameRegex) { $Reasons.Add('Security-sensitive rule name') }
                # Strong indicators mark a rule 'suspicious' for the score's +5 signal (RSS stays, plus these).
                $Suspicious = [bool]($ExternalForward -or ($Rule.DeleteMessage -eq $true) -or $MovesToLowVis -or $ActsOnAll -or ([string]$Rule.MoveToFolder -clike "*$SuspiciousFolder*"))
                $Rule | Select-Object *,
                @{ Name = 'RecentlyChanged'; Expression = { $_.Name -in $RecentRuleNames } },
                @{ Name = 'RiskReasons'; Expression = { $Reasons.ToArray() } },
                @{ Name = 'Suspicious'; Expression = { $Suspicious } },
                @{ Name = 'Risk'; Expression = { if ($Suspicious -or $Reasons.Count -gt 1) { 'High' } elseif ($Reasons.Count -eq 1) { 'Medium' } else { 'Review' } } }
            })

        Write-Information 'Getting trusted and blocked senders'
        $SafelistError = $null
        try {
            $JunkConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxJunkEmailConfiguration' -cmdParams @{ Identity = $UserName } -Anchor $UserName
            $TrustedSenders = @($JunkConfig.TrustedSendersAndDomains | Where-Object { $_ })
            $BlockedSenders = @($JunkConfig.BlockedSendersAndDomains | Where-Object { $_ })
            & $Mark 'Safelists' ([pscustomobject]@{ Complete = $true; Cap = $null; Error = $null; Count = $TrustedSenders.Count + $BlockedSenders.Count })
        } catch {
            $TrustedSenders = @()
            $BlockedSenders = @()
            $CippSafelistError = Get-CippException -Exception $_
            $SafelistError = "Could not retrieve the trusted/blocked senders list: $($CippSafelistError.NormalizedError)"
            & $Mark 'Safelists' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $SafelistError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve junk email configuration for $($UserName): $($CippSafelistError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSafelistError
        }

        Write-Information 'Getting safelist changes'
        try {
            $SafelistChanges = if ($auditLog -eq $false) { @() } else {
                if ($ChangeSearchError) { throw $ChangeSearchError.NormalizedError }
                $SafelistRecords = @($ChangeRecords | Where-Object { $SafelistOps -contains [string]$_.Operation })
                & $Mark 'SafelistChanges' ([pscustomobject]@{ Complete = [bool]$ChangeSearch.Complete; Cap = $ChangeSearch.Cap; Error = $null; Count = $SafelistRecords.Count })
                @($SafelistRecords | ForEach-Object { $_.AuditData } | Where-Object { $_ } | ForEach-Object {
                        $TrustedValue = ($_.Parameters | Where-Object { $_.Name -eq 'TrustedSendersAndDomains' }).Value
                        $BlockedValue = ($_.Parameters | Where-Object { $_.Name -eq 'BlockedSendersAndDomains' }).Value
                        [pscustomobject]@{
                            Operation = $_.Operation
                            UserKey   = $_.UserId
                            Date      = $_.CreationTime
                            ClientIP  = ConvertTo-CIPPBecHostAddress -Address ($_.ClientIP ?? $_.ClientIPAddress)
                            AuditData = $_
                            # the audit record carries the full new list, not a delta
                            Trusted   = if ($TrustedValue) { @(($TrustedValue -split ';').Trim() | Where-Object { $_ }) } else { $null }
                            Blocked   = if ($BlockedValue) { @(($BlockedValue -split ';').Trim() | Where-Object { $_ }) } else { $null }
                        }
                    })
            }
        } catch {
            $SafelistChanges = @()
            $CippSafelistChangeError = Get-CippException -Exception $_
            & $Mark 'SafelistChanges' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $CippSafelistChangeError.NormalizedError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve safelist changes for $($UserName): $($CippSafelistChangeError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSafelistChangeError
        }

        Write-Information 'Getting sharing link activity'
        try {
            $SharingChanges = if ($auditLog -eq $false) { @() } else {
                # link creation/changes only - AnonymousLinkUsed and access events are usage, not exposure changes
                if ($ChangeSearchError) { throw $ChangeSearchError.NormalizedError }
                $SharingRecords = @($ChangeRecords | Where-Object { $SharingOps -contains [string]$_.Operation })
                & $Mark 'SharingChanges' ([pscustomobject]@{ Complete = [bool]$ChangeSearch.Complete; Cap = $ChangeSearch.Cap; Error = $null; Count = $SharingRecords.Count })
                @($SharingRecords | ForEach-Object { $_.AuditData } | Where-Object { $_ } | ForEach-Object {
                        [pscustomobject]@{
                            Operation  = $_.Operation
                            UserKey    = $_.UserId
                            Date       = $_.CreationTime
                            Workload   = $_.Workload
                            FileName   = $_.SourceFileName
                            ItemUrl    = $_.ObjectId
                            Target     = $_.TargetUserOrGroupName
                            TargetType = $_.TargetUserOrGroupType
                            ClientIP   = ConvertTo-CIPPBecHostAddress -Address ($_.ClientIP ?? $_.ClientIPAddress)
                            AuditData  = $_
                        }
                    })
            }
        } catch {
            $SharingChanges = @()
            $CippSharingError = Get-CippException -Exception $_
            & $Mark 'SharingChanges' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $CippSharingError.NormalizedError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve sharing link activity for $($UserName): $($CippSharingError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSharingError
        }

        & $Phase 'SentMail' 'Walking the sent message trace'
        Write-Information 'Getting sent message trace'
        try {
            $SentTrace = Get-CIPPBecMessageTrace -TenantFilter $TenantFilter -SenderAddress $UserName -StartDate $startDate -EndDate $endDate -Anchor $UserName
            $SentMessagesRaw = @($SentTrace.Rows)
            $SentMessages = @($SentMessagesRaw | Select-Object MessageTraceId, Status, Subject, RecipientAddress, @{ Name = 'Received'; Expression = { ([datetime]$_.Received).ToString('u') } }, FromIP)
            & $Mark 'SentMessages' ([pscustomobject]@{ Complete = $SentTrace.Complete; Cap = $SentTrace.Cap; Error = $null; Count = $SentMessagesRaw.Count })
        } catch {
            $SentMessagesRaw = @()
            $SentMessages = @()
            $CippTraceError = Get-CippException -Exception $_
            & $Mark 'SentMessages' ([pscustomobject]@{ Complete = $false; Cap = $null; Error = $CippTraceError.NormalizedError; Count = 0 })
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve message trace for $($UserName): $($CippTraceError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippTraceError
        }

        # Outbound mail pattern analysis. The trace returns one row per recipient, so 'messages'
        # are distinct MessageTraceIds and 'recipients' are rows - one mail BCC'd to 200 people
        # and 200 individual sends are both blasts, just along different axes.
        try {
            $SentMail = $Heuristics.sentMail
            $RepeatSubjectMessages = [int]($SentMail.repeatSubjectMessages ?? 5)      # same subject sent as this many separate messages
            $RepeatSubjectRecipients = [int]($SentMail.repeatSubjectRecipients ?? 20) # or reaching this many recipients in total
            $MinRepeatedSubjectMessages = [int]($SentMail.minRepeatedSubjectMessages ?? 3)
            $BurstMessages = [int]($SentMail.burstMessages ?? 10)                      # distinct messages inside one window
            $BurstRecipients = [int]($SentMail.burstRecipients ?? 30)                  # or recipients inside one window
            $BurstWindowMinutes = [int]($SentMail.burstWindowMinutes ?? 10)
            $BurstWindowTicks = [timespan]::FromMinutes($BurstWindowMinutes).Ticks

            $RepeatedSubjects = @($SentMessagesRaw | Group-Object -Property { ([string]$_.Subject).Trim().ToLowerInvariant() } | ForEach-Object {
                    $MessageCount = @($_.Group.MessageTraceId | Select-Object -Unique).Count
                    $Times = @($_.Group.Received | Sort-Object)
                    [pscustomobject]@{
                        Subject        = if ([string]::IsNullOrWhiteSpace($_.Group[0].Subject)) { '(no subject)' } else { $_.Group[0].Subject }
                        MessageCount   = $MessageCount
                        RecipientCount = $_.Count
                        FirstSent      = if ($Times.Count -gt 0) { ([datetime]$Times[0]).ToString('u') } else { $null }
                        LastSent       = if ($Times.Count -gt 0) { ([datetime]$Times[-1]).ToString('u') } else { $null }
                        Flagged        = ($MessageCount -ge $RepeatSubjectMessages -or $_.Count -ge $RepeatSubjectRecipients)
                    }
                } | Where-Object { $_.MessageCount -ge $MinRepeatedSubjectMessages -or $_.Flagged } | Sort-Object -Property MessageCount -Descending | Select-Object -First 10)

            $Bursts = @($SentMessagesRaw | Where-Object { $_.Received } | Group-Object -Property { [long](([datetime]$_.Received).ToUniversalTime().Ticks / $BurstWindowTicks) } | ForEach-Object {
                    $MessageCount = @($_.Group.MessageTraceId | Select-Object -Unique).Count
                    if ($MessageCount -ge $BurstMessages -or $_.Count -ge $BurstRecipients) {
                        $TopSubject = ($_.Group | Group-Object -Property Subject | Sort-Object -Property Count -Descending | Select-Object -First 1).Name
                        [pscustomobject]@{
                            WindowStart    = [datetime]::new(([long]$_.Name) * $BurstWindowTicks, [System.DateTimeKind]::Utc).ToString('u')
                            WindowMinutes  = $BurstWindowMinutes
                            MessageCount   = $MessageCount
                            RecipientCount = $_.Count
                            TopSubject     = $TopSubject
                        }
                    }
                } | Sort-Object -Property RecipientCount -Descending | Select-Object -First 10)

            $SentMessageAnalysis = [PSCustomObject]@{
                TotalMessages       = @($SentMessagesRaw.MessageTraceId | Select-Object -Unique).Count
                TotalRecipients     = @($SentMessagesRaw).Count
                RepeatedSubjects    = $RepeatedSubjects
                FlaggedSubjectCount = @($RepeatedSubjects | Where-Object { $_.Flagged }).Count
                Bursts              = $Bursts
                Flagged             = (@($RepeatedSubjects | Where-Object { $_.Flagged }).Count -gt 0 -or @($Bursts).Count -gt 0)
            }
        } catch {
            $SentMessageAnalysis = [PSCustomObject]@{
                TotalMessages       = @($SentMessages).Count
                TotalRecipients     = @($SentMessages).Count
                RepeatedSubjects    = @()
                FlaggedSubjectCount = 0
                Bursts              = @()
                Flagged             = $false
            }
            Write-LogMessage -API 'BECRun' -message "Failed to analyze sent message patterns for $($UserName): $($_.Exception.Message)" -tenant $TenantFilter -sev Warning
        }

        & $Phase 'Tenant' 'Reading tenant users, MFA methods and applications'
        # The rogue-application catalog (CIPP MaliciousApps.json + the Huntress feed) keyed by lowercase
        # appId; shared with the consent collector so every section matches the same list.
        $RogueAppFeed = Get-CIPPBecRogueAppFeed
        $RogueApps = $RogueAppFeed.Apps
        $CatalogAppIds = @($RogueApps.Keys)
        $RogueMatch = { param($AppId) $Key = ([string]$AppId).ToLowerInvariant(); if ($Key -and $RogueApps.ContainsKey($Key)) { $RogueApps[$Key] } else { $null } }

        $Requests = @(
            @{
                id     = 'Users'
                url    = "users?`$select=id,displayName,userPrincipalName,userType,createdDateTime,lastPasswordChangeDateTime"
                method = 'GET'
            }
            @{
                id     = 'MFADevices'
                url    = "users/$($SuspectUser)/authentication/methods"
                method = 'GET'
            }
            @{
                id     = 'NewSPs'
                url    = "servicePrincipals?`$select=displayName,createdDateTime,appId,appDisplayName,publisher&`$filter=createdDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
                method = 'GET'
            }
            if ($HasIntune) {
                @{
                    id     = 'IntuneDevices'
                    url    = "users/$($SuspectUser)/managedDevices"
                    method = 'GET'
                }
            }
            @{
                id     = 'SuspectUser'
                url    = "users/$($SuspectUser)?`$select=id,displayName,userPrincipalName,usageLocation,country,city"
                method = 'GET'
            }
        )
        # Look for catalog apps present in the tenant regardless of age, chunked to keep each
        # 'in' filter within Graph's operand limit.
        $Requests = @($Requests) + @(for ($i = 0; $i -lt $CatalogAppIds.Count; $i += 15) {
                $Chunk = $CatalogAppIds[$i..([Math]::Min($i + 14, $CatalogAppIds.Count - 1))]
                @{
                    id     = "MaliciousSPs$i"
                    url    = "servicePrincipals?`$select=displayName,appId,accountEnabled,createdDateTime&`$filter=appId in ('$($Chunk -join "','")')"
                    method = 'GET'
                }
            })

        Write-Information 'Getting bulk requests'
        $GraphResults = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true
        foreach ($Pair in @(@{ Id = 'Users'; Name = 'TenantUsers' }, @{ Id = 'MFADevices'; Name = 'MFAMethods' }, @{ Id = 'NewSPs'; Name = 'NewApps' })) {
            $Response = $GraphResults | Where-Object { $_.id -eq $Pair.Id } | Select-Object -First 1
            $Failed = (-not $Response) -or ([int]$Response.status -ge 400)
            & $Mark $Pair.Name ([pscustomobject]@{ Complete = (-not $Failed); Cap = $null; Error = $(if ($Failed) { $Response.body.error.message ?? "Graph request $($Pair.Id) failed" } else { $null }); Count = @($Response.body.value).Count })
        }

        $PasswordChanges = (($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value | Where-Object { $_.lastPasswordChangeDateTime -ge $startDate }) ?? @()
        $NewUsers = (($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value | Where-Object { $_.createdDateTime -ge $startDate }) ?? @()
        $MFADevices = ($GraphResults | Where-Object { $_.id -eq 'MFADevices' }).body.value ?? @()
        $NewSPs = ($GraphResults | Where-Object { $_.id -eq 'NewSPs' }).body.value ?? @()

        $SuspectUserDetail = ($GraphResults | Where-Object { $_.id -eq 'SuspectUser' }).body
        if ($SuspectUserDetail.error) { $SuspectUserDetail = $null }
        $UsageLocation = if ([string]::IsNullOrWhiteSpace($SuspectUserDetail.usageLocation)) { $null } else { $SuspectUserDetail.usageLocation }

        # Flag service principals added during the window that match the malicious catalog
        $NewSPs = @(foreach ($SP in @($NewSPs)) {
                $CatalogEntry = & $RogueMatch $SP.appId
                $Match = if ($CatalogEntry) {
                    [PSCustomObject]@{ Name = $CatalogEntry.Name; Categories = @($CatalogEntry.Categories); Description = $CatalogEntry.Description; Source = $CatalogEntry.Source }
                } else { $null }
                $SP | Select-Object *, @{ Name = 'MaliciousMatch'; Expression = { $Match } }
            })

        # Catalog apps present in the tenant at all - persistence via OAuth consent survives a
        # password reset, so an old grant matters as much as a new one.
        $MaliciousSPResults = @($GraphResults | Where-Object { $_.id -like 'MaliciousSPs*' -and [int]$_.status -lt 400 } | ForEach-Object { $_.body.value } | Where-Object { $_ })
        $MaliciousSPs = @(foreach ($SP in $MaliciousSPResults) {
                $CatalogEntry = & $RogueMatch $SP.appId
                [PSCustomObject]@{
                    displayName     = $SP.displayName
                    appId           = $SP.appId
                    accountEnabled  = $SP.accountEnabled
                    createdDateTime = $SP.createdDateTime
                    CatalogName     = $CatalogEntry.Name
                    Categories      = @($CatalogEntry.Categories)
                    Description     = $CatalogEntry.Description
                    Source          = $CatalogEntry.Source
                }
            })

        # Intune managed devices for the suspect user - surface Graph failures instead of a silent empty list
        $IntuneDevicesError = $null
        $IntuneDevices = @()
        if (-not $HasIntune) {
            & $Mark 'IntuneDevices' (& $Skip 'requires an Intune licence')
        } else {
            $IntuneResponse = $GraphResults | Where-Object { $_.id -eq 'IntuneDevices' } | Select-Object -First 1
            if (-not $IntuneResponse) {
                $IntuneDevicesError = 'Intune device query did not return a response'
            } elseif ([int]$IntuneResponse.status -ge 400) {
                # Graph proxies this call to Intune's DeviceFE service, which returns its own JSON
                # error blob as the Graph error message. Unwrap it so the report shows a readable
                # sentence instead of raw JSON, keeping the Activity ID for Microsoft support cases.
                $RawIntuneError = $IntuneResponse.body.error.message
                $IntuneDevicesError = $RawIntuneError
                if ($RawIntuneError -match '^\s*\{') {
                    try {
                        $ParsedIntuneError = $RawIntuneError | ConvertFrom-Json -ErrorAction Stop
                        if (-not [string]::IsNullOrWhiteSpace($ParsedIntuneError.Message)) {
                            $IntuneDevicesError = $ParsedIntuneError.Message
                        }
                    } catch { Write-Verbose 'Intune error body is not JSON; keeping the raw message' }
                }
                if ($IntuneDevicesError -like 'An error has occurred*') {
                    $ActivityId = [regex]::Match($IntuneDevicesError, 'Activity ID: ([0-9a-fA-F-]{36})').Groups[1].Value
                    $IntuneDevicesError = "Intune returned an unexpected error (HTTP $($IntuneResponse.status)). This is a failure inside the Intune service itself and is usually transient. Rerun the check to retry.$(if ($ActivityId) { " Microsoft support reference (Activity ID): $ActivityId" })"
                }
                if ([string]::IsNullOrWhiteSpace($IntuneDevicesError)) {
                    $IntuneDevicesError = "Intune device query failed with status $($IntuneResponse.status)"
                }
                Write-LogMessage -API 'BECRun' -message "Failed to retrieve Intune devices for $($UserName): $IntuneDevicesError" -tenant $TenantFilter -sev Warning
            } else {
                $IntuneDevicesRaw = $IntuneResponse.body.value ?? @()
                $IntuneDevices = @(
                    foreach ($Device in @($IntuneDevicesRaw)) {
                        [PSCustomObject]@{
                            id                     = $Device.id
                            deviceName             = $Device.deviceName
                            operatingSystem        = $Device.operatingSystem
                            osVersion              = $Device.osVersion
                            complianceState        = $Device.complianceState
                            enrolledDateTime       = if ($Device.enrolledDateTime) { ([datetime]$Device.enrolledDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                            lastSyncDateTime       = if ($Device.lastSyncDateTime) { ([datetime]$Device.lastSyncDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                            deviceEnrollmentType   = $Device.deviceEnrollmentType
                            manufacturer           = $Device.manufacturer
                            model                  = $Device.model
                            serialNumber           = $Device.serialNumber
                            userPrincipalName      = $Device.userPrincipalName
                            managedDeviceOwnerType = $Device.managedDeviceOwnerType
                        }
                    }
                )
            }
            & $Mark 'IntuneDevices' ([pscustomobject]@{ Complete = (-not $IntuneDevicesError); Cap = $null; Error = $IntuneDevicesError; Count = $IntuneDevices.Count })
        }

        # ---------------------------------------------------------------------------------
        # The deeper collectors. Each one degrades to an Error marker - a failed collector
        # never fails the run.
        # ---------------------------------------------------------------------------------
        $MailboxState = $null
        $Delegations = @()
        $MailboxAddIns = @()
        $TransportRuleChanges = @()
        $TransportRulesFlagged = @()
        $ReceivedMailFindings = @()
        $ReceivedMailSummary = $null
        $DefenderDetections = @()
        $AcceptedDomains = @()
        & $Phase 'MailboxInventory' 'Reading mailbox state, delegations and add-ins'
        Write-Information 'Full scope: accepted domains'
        try {
            $AcceptedDomains = @((New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AcceptedDomain' -Anchor $UserName).DomainName | Where-Object { $_ } | ForEach-Object { [string]$_ })
        } catch {
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve accepted domains for $($TenantFilter): $((Get-NormalizedError -message $_.Exception.Message))" -tenant $TenantFilter -sev Warning
        }
        # Without accepted domains the external-trustee and typosquat checks fall back to the user's own domain.
        if ($AcceptedDomains.Count -eq 0 -and $UserName -match '@') { $AcceptedDomains = @(($UserName -split '@')[-1]) }

        $Collect = {
            param($Name, [scriptblock]$Body)
            try {
                & $Body
            } catch {
                $CollectorError = Get-CippException -Exception $_
                Write-LogMessage -API 'BECRun' -message "BEC collector $Name failed for $($UserName): $($CollectorError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CollectorError
                New-CIPPBecCollectorResult -Data @() -Error $CollectorError.NormalizedError
            }
        }

        Write-Information 'Full scope: mailbox inventory'
        $Inventory = & $Collect 'MailboxInventory' { Get-CIPPBecMailboxInventory -TenantFilter $TenantFilter -UserPrincipalName $UserName -Heuristics $Heuristics -AcceptedDomains $AcceptedDomains }
        if ($Inventory.PSObject.Properties['MailboxState']) {
            & $Mark 'MailboxState' $Inventory.MailboxState
            & $Mark 'Delegations' $Inventory.Delegations
            & $Mark 'MailboxAddIns' $Inventory.AddIns
            $MailboxState = $Inventory.MailboxState.Data
            $Delegations = @($Inventory.Delegations.Data)
            $MailboxAddIns = @($Inventory.AddIns.Data)
            # Exchange returns GrantSendOnBehalfTo (and some folder members) as directory ids; show the UPN.
            $UserById = @{}
            foreach ($TenantUser in @(($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value)) { if ($TenantUser.id) { $UserById[[string]$TenantUser.id] = [string]$TenantUser.userPrincipalName } }
            # A delegation whose grant is in this window's audit log (Add-MailboxPermission / Add-RecipientPermission /
            # folder grants on this mailbox) is the classic persistence move and is flagged even for an internal trustee.
            $RecentTrustees = @($PermissionsLog | Where-Object { $_.TargetsSuspect -and $_.Operation -match '^(Add-|Update)' -and $_.Trustee } | ForEach-Object { $_.Trustee.ToLowerInvariant() })
            foreach ($Delegation in $Delegations) {
                if ($Delegation.Trustee -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -and $UserById.ContainsKey($Delegation.Trustee)) {
                    $Delegation | Add-Member -NotePropertyName 'TrusteeId' -NotePropertyValue $Delegation.Trustee -Force
                    $Delegation.Trustee = $UserById[$Delegation.Trustee]
                }
                $GrantedInWindow = [bool]($Delegation.Trustee -and $RecentTrustees -contains $Delegation.Trustee.ToLowerInvariant())
                $Delegation | Add-Member -NotePropertyName 'GrantedInWindow' -NotePropertyValue $GrantedInWindow -Force
                if ($GrantedInWindow) { $Delegation.Flagged = $true }
            }
            $Delegations = @($Delegations | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, PermissionType, Trustee)
            # ForwardingAddress (internal forwarding) is a directory id too
            if ($MailboxState -and $MailboxState.ForwardingAddress -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -and $UserById.ContainsKey([string]$MailboxState.ForwardingAddress)) {
                $MailboxState | Add-Member -NotePropertyName 'ForwardingAddressId' -NotePropertyValue $MailboxState.ForwardingAddress -Force
                $MailboxState.ForwardingAddress = $UserById[[string]$MailboxState.ForwardingAddress]
            }
        } else {
            & $Mark 'MailboxState' $Inventory; & $Mark 'Delegations' $Inventory; & $Mark 'MailboxAddIns' $Inventory
        }

        & $Phase 'Grants' 'Reading application consents'
        Write-Information 'Full scope: user grants'
        $Grants = & $Collect 'UserGrants' { Get-CIPPBecUserGrants -TenantFilter $TenantFilter -UserId $SuspectUser -Heuristics $Heuristics -RogueAppFeed $RogueAppFeed }
        & $Mark 'UserGrants' $Grants
        $UserGrants = @($Grants.Data)

        & $Phase 'TransportRules' 'Reading transport rules and their changes'
        Write-Information 'Full scope: transport rules'
        $Transport = & $Collect 'TransportRules' { Get-CIPPBecTransportRules -TenantFilter $TenantFilter -StartDate $startDate -EndDate $endDate -Heuristics $Heuristics -Anchor $UserName }
        if ($Transport.PSObject.Properties['Changes']) {
            & $Mark 'TransportRuleChanges' $Transport.Changes
            & $Mark 'TransportRulesFlagged' $Transport.Flagged
            $TransportRuleChanges = @($Transport.Changes.Data)
            $TransportRulesFlagged = @($Transport.Flagged.Data)
        } else {
            & $Mark 'TransportRuleChanges' $Transport; & $Mark 'TransportRulesFlagged' $Transport
        }

        & $Phase 'ReceivedMail' 'Reading the received-mail trace and Defender verdicts'
        Write-Information 'Full scope: received mail'
        $Received = & $Collect 'ReceivedMail' { Get-CIPPBecReceivedMailFindings -TenantFilter $TenantFilter -UserPrincipalName $UserName -StartDate $startDate -EndDate $endDate -Heuristics $Heuristics -AcceptedDomains $AcceptedDomains -Anchor $UserName -IncludeDefender:$HasDefenderP2 }
        if ($Received.PSObject.Properties['Findings']) {
            & $Mark 'ReceivedMailFindings' $Received.Findings
            & $Mark 'DefenderDetections' $Received.Defender
            $ReceivedMailFindings = @($Received.Findings.Data)
            $ReceivedMailSummary = $Received.Findings.Summary
            $DefenderDetections = @($Received.Defender.Data)
        } else {
            & $Mark 'ReceivedMailFindings' $Received; & $Mark 'DefenderDetections' $Received
        }

        & $Phase 'Directory' 'Reading directory audits, registered devices and non-interactive sign-ins'
        Write-Information 'Full scope: directory audits'
        $Audits = & $Collect 'DirectoryAudits' { Get-CIPPBecDirectoryAudits -TenantFilter $TenantFilter -UserId $SuspectUser -StartDate $startDate -Heuristics $Heuristics }
        & $Mark 'DirectoryAudits' $Audits
        $DirectoryAudits = @($Audits.Data)

        Write-Information 'Full scope: registered devices'
        $Registered = & $Collect 'RegisteredDevices' { Get-CIPPBecRegisteredDevices -TenantFilter $TenantFilter -UserId $SuspectUser -StartDate $startDate }
        & $Mark 'RegisteredDevices' $Registered
        $RegisteredDevices = @($Registered.Data)

        Write-Information 'Full scope: non-interactive sign-ins'
        $NonInteractive = & $Collect 'NonInteractiveSignIns' { Get-CIPPBecNonInteractiveSignIns -TenantFilter $TenantFilter -UserId $SuspectUser -UsageLocation $UsageLocation -StartDate $startDate }
        & $Mark 'NonInteractiveSignIns' $NonInteractive
        $NonInteractiveSignIns = @($NonInteractive.Data)

        & $Phase 'Activity' 'Reading mailbox activity counts and Identity Protection state'
        Write-Information 'Full scope: mailbox activity'
        $Activity = if ($auditLog -eq $false) { New-CIPPBecCollectorResult -Data @() -Error 'Unified audit log ingestion is disabled for this tenant' } else { & $Collect 'MailActivity' { Get-CIPPBecMailActivity -TenantFilter $TenantFilter -UserPrincipalName $UserName -StartDate $startDate -EndDate $endDate -Heuristics $Heuristics -Anchor $UserName } }
        & $Mark 'MailActivity' $Activity
        $MailActivity = @($Activity.Data)
        $MailActivitySummary = $Activity.Summary
        # the raw records, for the attacker-activity pass (not stored)
        $MailRecords = @($Activity.Records | Where-Object { $_ })

        Write-Information 'Full scope: risk state'
        $Risk = if ($HasEntraP2) { & $Collect 'RiskState' { Get-CIPPBecRiskState -TenantFilter $TenantFilter -UserId $SuspectUser -StartDate $startDate } } else { & $Skip 'requires Entra ID P2 (Identity Protection)' }
        & $Mark 'RiskState' $Risk
        $RiskState = $Risk.Data

        # Who did it: a partner (GDAP) identity, CIPP's own service principal, an application or the
        # tenant's own user. Stamped on every actor-bearing row so partner and CIPP actions read as such
        # (the case page lists them together) instead of as unknown actors. The score is not changed.
        $PartnerUsers = try { Get-CIPPPartnerUserLookup } catch { Write-Information "BEC: partner user lookup unavailable: $($_.Exception.Message)"; @{} }
        $StampActor = {
            param($Rows, $Property, $TypeProperty, $IdProperty)
            foreach ($Row in @($Rows)) {
                if (-not $Row) { continue }
                $Type = if ($TypeProperty) { [string]$Row.$TypeProperty } else { 'User' }
                $AppId = if ($IdProperty -and $Type -eq 'Application') { [string]$Row.$IdProperty } else { $null }
                $Who = Resolve-CIPPAuditActor -Actor ([string]$Row.$Property) -ActorType $Type -AppId $AppId -PartnerUserLookup $PartnerUsers
                $Row | Add-Member -NotePropertyName 'ActorKind' -NotePropertyValue $Who.Kind -Force
                $Row | Add-Member -NotePropertyName 'ActorResolved' -NotePropertyValue $Who.Actor -Force
            }
        }
        & $StampActor $RuleChangesLog 'UserKey'
        & $StampActor $PermissionsLog 'UserId'
        & $StampActor $SafelistChanges 'UserKey'
        & $StampActor $SharingChanges 'UserKey'
        & $StampActor $TransportRuleChanges 'Actor'
        & $StampActor $DirectoryAudits 'InitiatedBy' 'InitiatedByType' 'InitiatedById'
        & $StampActor $MailActivity 'Actor'

        # Which addresses are the attacker's: sign-in baseline, CIPP's IP allow/block list and the
        # tenant's own lists, geo, and the other accounts on each address. The IP review re-run calls
        # the same analysis with the investigator's overrides.
        & $Phase 'IPAnalysis' 'Establishing attacker IPs from the sign-in baseline, IP lists and other accounts'
        Write-Information 'Full scope: IP analysis'
        $IPDraft = [pscustomobject]@{
            SuspectUserSignIns       = @($SuspectUserSignIns)
            NonInteractiveSignIns    = @($NonInteractiveSignIns)
            NewRules                 = @($RulesLog)
            InboxRuleChanges         = @($RuleChangesLog)
            MailboxPermissionChanges = @($PermissionsLog)
            SafelistChanges          = @($SafelistChanges)
            SharingChanges           = @($SharingChanges)
            TransportRuleChanges     = @($TransportRuleChanges)
            DirectoryAudits          = @($DirectoryAudits)
            SentMessages             = @($SentMessages)
            SentMessageAnalysis      = $SentMessageAnalysis
            MailActivity             = @($MailActivity)
        }
        # the technician who started the run: their address is theirs, not the user's or the attacker's
        $TechnicianIPs = @(if ($Item.RequestedFromIP) { [pscustomobject]@{ IP = [string]$Item.RequestedFromIP; By = [string]$Item.RequestedBy } })
        $IPAnalysis = & $Collect 'IPAnalysis' { Invoke-CIPPBecIPAnalysis -TenantFilter $TenantFilter -UserId $SuspectUser -UserPrincipalName $UserName -Results $IPDraft -Heuristics $Heuristics -WindowStart $startDate -UsageLocation $UsageLocation -Anchor $UserName -SampleColleagues -TechnicianIPs $TechnicianIPs }
        if ($IPAnalysis.PSObject.Properties['Verdicts']) {
            & $Mark 'SignInBaseline' $IPAnalysis.Baseline
            & $Mark 'IPGuidance' $IPAnalysis.Guidance
            & $Mark 'IPPeers' $IPAnalysis.PeersResult
            & $Mark 'IPVerdicts' ([pscustomobject]@{ Complete = $true; Count = @($IPAnalysis.Verdicts).Count })
            $IPVerdicts = @($IPAnalysis.Verdicts)
            $IPBaseline = $IPAnalysis.Baseline.Data
            $IPGuidance = @($IPAnalysis.Guidance.Data)
            $IPPeers = @($IPAnalysis.Peers.Values)
        } else {
            & $Mark 'SignInBaseline' $IPAnalysis; & $Mark 'IPGuidance' $IPAnalysis; & $Mark 'IPPeers' $IPAnalysis; & $Mark 'IPVerdicts' $IPAnalysis
            $IPVerdicts = @(); $IPBaseline = $null; $IPGuidance = @(); $IPPeers = @()
        }
        Set-CIPPBecIPVerdictStamp -Results $IPDraft -Verdicts $IPVerdicts

        # What the attacker-side addresses did, item by item: mail opened/synced/deleted/moved/sent,
        # files touched, sharing links used, Forms built - and the other mailboxes the account reaches.
        & $Phase 'AttackerActivity' 'Reading what the attacker addresses opened, sent, downloaded and shared'
        Write-Information 'Full scope: attacker activity'
        $KnownSubjects = @{}
        if ($Received.MessageIndex -is [hashtable]) { foreach ($Key in $Received.MessageIndex.Keys) { $KnownSubjects[$Key] = $Received.MessageIndex[$Key] } }
        foreach ($Row in @($SentMessagesRaw | Where-Object { $_.MessageId })) { $KnownSubjects[[string]$Row.MessageId] = [string]$Row.Subject }
        $Attacker = & $Collect 'AttackerActivity' { Get-CIPPBecAttackerActivity -TenantFilter $TenantFilter -UserPrincipalName $UserName -StartDate $startDate -EndDate $endDate -Heuristics $Heuristics -Verdicts $IPVerdicts -SignIns $SuspectUserSignIns -NonInteractiveSignIns $NonInteractiveSignIns -MailRecords $MailRecords -SharingChanges $SharingChanges -KnownSubjects $KnownSubjects -Anchor $UserName }
        if ($Attacker.PSObject.Properties['Mail']) {
            & $Mark 'AttackerMailActivity' $Attacker.Mail
            & $Mark 'AttackerFileActivity' $Attacker.Files
            & $Mark 'LinkUsage' $Attacker.LinkUsage
            & $Mark 'FormsActivity' $Attacker.Forms
            $AttackerMailActivity = @($Attacker.Mail.Data); $AttackerMailSummary = $Attacker.Mail.Summary
            $AttackerFileActivity = @($Attacker.Files.Data); $AttackerFileSummary = $Attacker.Files.Summary
            $LinkUsage = @($Attacker.LinkUsage.Data)
            $FormsActivity = @($Attacker.Forms.Data); $FormsSummary = $Attacker.Forms.Summary
        } else {
            foreach ($Name in @('AttackerMailActivity', 'AttackerFileActivity', 'LinkUsage', 'FormsActivity')) { & $Mark $Name $Attacker }
            $AttackerMailActivity = @(); $AttackerMailSummary = $null; $AttackerFileActivity = @(); $AttackerFileSummary = $null; $LinkUsage = @(); $FormsActivity = @(); $FormsSummary = $null
        }
        $Delegated = & $Collect 'DelegatedAccess' { Get-CIPPBecDelegatedAccess -TenantFilter $TenantFilter -UserPrincipalName $UserName -UserDisplayName ([string]$SuspectUserDetail.displayName) -PermissionChanges $PermissionsLog -MailActivity $MailActivity -AttackerMail $AttackerMailActivity }
        & $Mark 'DelegatedAccess' $Delegated
        $DelegatedAccess = @($Delegated.Data)
        # The other accounts the attacker addresses reached: tenant-wide sign-ins and audit log per address
        $AnalysisPeers = if ($IPAnalysis.PSObject.Properties['Peers'] -and $IPAnalysis.Peers -is [hashtable]) { $IPAnalysis.Peers } else { @{} }
        $Blast = & $Collect 'BlastRadius' { Get-CIPPBecBlastRadius -TenantFilter $TenantFilter -UserId $SuspectUser -UserPrincipalName $UserName -Verdicts $IPVerdicts -Peers $AnalysisPeers -StartDate $startDate -EndDate $endDate -Heuristics $Heuristics -Anchor $UserName }
        & $Mark 'BlastRadius' $Blast
        $BlastRadius = @($Blast.Data)

        # Geo-locate the client IPs behind rule changes, safelist changes, sharing changes, sent
        # mail and (Full scope) transport-rule changes, directory audits and mailbox activity so
        # activity can be compared against the user's assigned usage location. Sign-ins carry
        # their own location from Graph. A geo failure degrades to no location, never a failed run.
        & $Phase 'Score' 'Resolving locations and computing the threat score'
        Write-Information 'Resolving IP locations'
        $GeoIPCandidates = [System.Collections.Generic.List[string]]::new()
        $GeoRows = @($RuleChangesLog) + @($SafelistChanges) + @($SharingChanges) + @($PermissionsLog | Where-Object { $_.TargetsSuspect }) + @($TransportRuleChanges) + @($DirectoryAudits) + @($MailActivity)
        foreach ($Row in $GeoRows) { if ($Row.ClientIP) { $GeoIPCandidates.Add([string]$Row.ClientIP) } }
        foreach ($Row in @($SentMessages)) { if ($Row.FromIP) { $GeoIPCandidates.Add([string]$Row.FromIP) } }
        $GeoMap = @{}
        if ($GeoIPCandidates.Count -gt 0) {
            try {
                $GeoMap = Get-CIPPGeoIPLocationBatch -IPs $GeoIPCandidates
            } catch {
                Write-LogMessage -API 'BECRun' -message "Failed to geo-locate activity IPs for $($UserName): $($_.Exception.Message)" -tenant $TenantFilter -sev Warning
                $GeoMap = @{}
            }
        }
        $GetGeo = {
            param($RawIP)
            if ([string]::IsNullOrWhiteSpace($RawIP)) { return $null }
            # same normalization the batch helper applies to its keys (strip :port and brackets)
            $Clean = ConvertTo-CIPPBecHostAddress -Address $RawIP
            if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }
            return $GeoMap[$Clean]
        }
        # $null when either side of the comparison is unknown - only a definite mismatch counts as foreign
        $TestForeign = {
            param($Country)
            if (-not $UsageLocation -or [string]::IsNullOrWhiteSpace($Country) -or $Country -eq 'Unknown') { return $null }
            return ($Country -ne $UsageLocation)
        }

        foreach ($Row in $GeoRows) {
            $Geo = & $GetGeo $Row.ClientIP
            $Row | Add-Member -NotePropertyMembers ([ordered]@{
                    Country         = $Geo.CountryOrRegion
                    City            = $Geo.City
                    ForeignLocation = (& $TestForeign $Geo.CountryOrRegion)
                }) -Force
        }
        foreach ($Row in @($SentMessages)) {
            $Geo = & $GetGeo $Row.FromIP
            $Row | Add-Member -NotePropertyMembers ([ordered]@{
                    Country         = $Geo.CountryOrRegion
                    City            = $Geo.City
                    ForeignLocation = (& $TestForeign $Geo.CountryOrRegion)
                }) -Force
        }
        foreach ($Row in @($SuspectUserSignIns)) {
            $Row | Add-Member -NotePropertyName 'ForeignLocation' -NotePropertyValue (& $TestForeign $Row.Country) -Force
        }

        $SignInCountries = @($SuspectUserSignIns | Where-Object { $_.Country } | Group-Object -Property Country | Sort-Object -Property Count -Descending | ForEach-Object {
                [PSCustomObject]@{ Country = $_.Name; Count = $_.Count }
            })
        $LocationAnalysis = [PSCustomObject]@{
            UsageLocation                     = $UsageLocation
            UserRegisteredCountry             = $SuspectUserDetail.country
            SignInCountries                   = $SignInCountries
            ForeignSignInCount                = @($SuspectUserSignIns | Where-Object { $_.ForeignLocation -eq $true }).Count
            # failed foreign attempts are password-spray background noise; only a success proves access
            ForeignSuccessfulSignInCount      = @($SuspectUserSignIns | Where-Object { $_.ForeignLocation -eq $true -and $_.Status -eq 'Success' }).Count
            ForeignRuleChangeCount            = @($RuleChangesLog | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignSafelistChangeCount        = @($SafelistChanges | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignSharingChangeCount         = @($SharingChanges | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignSentMessageCount           = @($SentMessages | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignNonInteractiveSignInCount  = @($NonInteractiveSignIns | Where-Object { $_.ForeignLocation -eq $true -and $_.Status -eq 'Success' }).Count
            ForeignTransportRuleChangeCount   = @($TransportRuleChanges | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignDirectoryAuditCount        = @($DirectoryAudits | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignMailActivityCount          = @($MailActivity | Where-Object { $_.ForeignLocation -eq $true }).Count
            Note                              = if (-not $UsageLocation) { 'The user has no usage location assigned in Entra ID, so activity cannot be compared against an expected country. Countries are still listed for manual review.' } else { $null }
        }

        $Results = [PSCustomObject]@{
            CaseId                   = $CaseId
            UserPrincipalName        = $UserName
            AddedApps                = @($NewSPs)
            MaliciousSPs             = @($MaliciousSPs)
            SuspectUserSignIns       = @($SuspectUserSignIns)
            SuspectUserSignInsError  = $SuspectUserSignInsError
            SuspectUserDevices       = @($Devices)
            NewRules                 = @($RulesLog)
            InboxRuleChanges         = @($RuleChangesLog)
            SentMessages             = @($SentMessages)
            SentMessageAnalysis      = $SentMessageAnalysis
            MailboxPermissionChanges = @($PermissionsLog)
            NewUsers                 = @($NewUsers)
            MFADevices               = @($MFADevices | Where-Object { $_.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod' })
            ChangedPasswords         = @($PasswordChanges)
            TrustedSenders           = @($TrustedSenders)
            BlockedSenders           = @($BlockedSenders)
            SafelistChanges          = @($SafelistChanges)
            SafelistError            = $SafelistError
            SharingChanges           = @($SharingChanges)
            IntuneDevices            = @($IntuneDevices)
            IntuneDevicesError       = $IntuneDevicesError
            LocationAnalysis         = $LocationAnalysis
            # The deeper collectors
            MailboxState             = $MailboxState
            Delegations              = @($Delegations)
            MailboxAddIns            = @($MailboxAddIns)
            UserGrants               = @($UserGrants)
            TransportRuleChanges     = @($TransportRuleChanges)
            TransportRulesFlagged    = @($TransportRulesFlagged)
            ReceivedMailFindings     = @($ReceivedMailFindings)
            ReceivedMailSummary      = $ReceivedMailSummary
            DefenderDetections       = @($DefenderDetections)
            DirectoryAudits          = @($DirectoryAudits)
            RegisteredDevices        = @($RegisteredDevices)
            NonInteractiveSignIns    = @($NonInteractiveSignIns)
            MailActivity             = @($MailActivity)
            MailActivitySummary      = $MailActivitySummary
            # the attacker-IP picture: one verdict per address plus the evidence behind it
            IPVerdicts               = @($IPVerdicts)
            IPBaseline               = $IPBaseline
            IPGuidance               = @($IPGuidance)
            IPPeers                  = @($IPPeers)
            IPOverrides              = @()
            IPTechnicians            = @($TechnicianIPs)
            # item-level detail of the attacker-side addresses, and the mailboxes the account reaches
            AttackerMailActivity     = @($AttackerMailActivity)
            AttackerMailSummary      = $AttackerMailSummary
            AttackerFileActivity     = @($AttackerFileActivity)
            AttackerFileSummary      = $AttackerFileSummary
            LinkUsage                = @($LinkUsage)
            FormsActivity            = @($FormsActivity)
            FormsSummary             = $FormsSummary
            DelegatedAccess          = @($DelegatedAccess)
            BlastRadius              = @($BlastRadius)
            RiskState                = $RiskState
            Completeness             = [pscustomobject]$Completeness
            AnalysisWindowDays       = $WindowDays
            ExtractedAt              = (Get-Date)
            ExtractResult            = $ExtractResult
        }
        $Score = Get-CIPPBecScore -Results $Results -Heuristics $Heuristics
        $Results | Add-Member -NotePropertyName 'Score' -NotePropertyValue $Score -Force

        $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Results $Results -Properties @{
            UserId            = [string]$SuspectUser
            UserPrincipalName = [string]$UserName
            DisplayName       = [string]$SuspectUserDetail.displayName
            Status            = 'Completed'
            Score             = [int]$Score.Value
            Level             = [string]$Score.Level
            ExtractedAt       = $Results.ExtractedAt.ToUniversalTime().ToString('o')
            IncompleteCount   = @($Completeness.Values | Where-Object { -not $_.Complete }).Count
        }
        Write-LogMessage -API 'BECRun' -message "BEC check run for $UserName - threat level $($Score.Level) ($($Score.Value)) [case $CaseId]" -tenant $TenantFilter -sev 'Info'
        & $Step 'Score' 'succeeded' "Threat level $($Score.Level) ($($Score.Value))"
        Set-CIPPAsyncDeploymentStatus -JobId $CaseId -Name $ProgressName -Status 'succeeded' -Logs "Completed run $CaseId with threat level $($Score.Level) ($($Score.Value))"
    } catch {
        $errMessage = Get-NormalizedError -message $_.Exception.Message
        $CippError = Get-CippException -Exception $_
        Write-LogMessage -API 'BECRun' -message "Error Running BEC for $($UserName): $errMessage [case $CaseId]" -tenant $TenantFilter -sev 'Error' -LogData $CIPPError
        if ($Progress.Current) { & $Step $Progress.Current 'failed' $errMessage }
        Set-CIPPAsyncDeploymentStatus -JobId $CaseId -Name $ProgressName -Status 'failed' -Logs $errMessage
        try {
            $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{
                UserId            = [string]$SuspectUser
                UserPrincipalName = [string]$UserName
                Status            = 'Error'
                ErrorMessage      = [string]$errMessage
                ExtractedAt       = (Get-Date).ToUniversalTime().ToString('o')
            }
        } catch {
            Write-Information "BEC: could not record the failed run $CaseId`: $($_.Exception.Message)"
        }
    } finally {
        Set-CippBecCaseContext -CaseId $null
    }
}
