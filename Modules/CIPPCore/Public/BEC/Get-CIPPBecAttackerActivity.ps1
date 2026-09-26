function Get-CIPPBecAttackerActivity {
    <#
    .SYNOPSIS
        Collects item-level detail of what the attacker's addresses did: mail opened, synced, deleted,
        moved and sent, files touched, sharing links used, and Microsoft Forms built from the account.
    .DESCRIPTION
        Only the attacker side is kept in detail - addresses whose verdict is Compromised,
        LikelyAttacker, Suspicious or Unknown - so the user's own day-to-day activity stays as the
        counts it already is (MailActivity).
        Every record is tied to an address, even when the audit log left it out or recorded a
        Microsoft front-end address: its own client address, else the sign-in behind its token
        (AppAccessContext.UniqueTokenId), else its Entra session (AppAccessContext.AADSessionId),
        else another record of the same mailbox session. The most direct link with a verdict wins -
        the record's own address over its token, its token over a shared session - and a Microsoft
        front end (Service) never counts as the actor. Only among the addresses of one session does
        the worst verdict win: a session also carries the user's own addresses, so it must not
        outrank where the request itself came from.
        - Mail: from the mailbox records the MailActivity search already read (no second search):
          one row per message opened (internet message id + folder, named from the message trace),
          per folder synced by a desktop client (the whole folder counts as taken), per item deleted,
          moved or sent, per attachment read, plus folder-permission, calendar-delegation, mailbox
          setting and mailbox search events.
        - Files: one SharePoint/OneDrive search filtered to the attacker-side addresses.
        - Link usage: the anonymous, company and specific-people links created in the window, and who
          opened them (these are logged against the opener, so they are searched by item).
        - Forms: every Microsoft Forms action by the account with its verdict; for forms created,
          edited, shared or sent from an attacker-side address, how many people opened or answered
          them and whether Microsoft flagged them as phishing.
        Returns { Mail, Files, LinkUsage, Forms, Subjects } where each is a collector result (Mail and
        Forms carry a Summary).
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The investigated user.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object (attackerActivity section, caps).
    .PARAMETER Verdicts
        The IP verdict rows.
    .PARAMETER SignIns
        The window's interactive sign-ins (IPAddress, UniqueTokenId, SessionId).
    .PARAMETER NonInteractiveSignIns
        The window's non-interactive sign-ins.
    .PARAMETER MailRecords
        The raw mailbox audit records from Get-CIPPBecMailActivity.
    .PARAMETER SharingChanges
        The sharing-link changes of the window (ItemUrl / ObjectId).
    .PARAMETER KnownSubjects
        Subjects already known by internet message id (the run's sent and received traces).
    .PARAMETER Anchor
        Anchor mailbox for the Exchange requests.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [Parameter(Mandatory = $true)]$Heuristics,
        [object[]]$Verdicts = @(),
        [object[]]$SignIns = @(),
        [object[]]$NonInteractiveSignIns = @(),
        [object[]]$MailRecords = @(),
        [object[]]$SharingChanges = @(),
        [hashtable]$KnownSubjects = @{},
        [string]$Anchor
    )

    $Cfg = $Heuristics.attackerActivity
    $MaxPages = [int]($Heuristics.caps.auditLogPages ?? 10)
    $AttackerSide = @('Compromised', 'LikelyAttacker', 'Suspicious', 'Unknown')
    $Rank = @{ Compromised = 0; LikelyAttacker = 1; Suspicious = 2; Unknown = 3; LikelyUser = 4; Safe = 5; Service = 6 }
    $HostOf = { param($Value) ConvertTo-CIPPBecHostAddress -Address ([string]$Value) }
    $VerdictOf = @{}
    foreach ($Row in @($Verdicts | Where-Object { $_ -and $_.IP })) { $VerdictOf[[string]$Row.IP] = [string]$Row.Verdict }
    # audit CreationTime is UTC without a zone: read it as UTC, not as the host's local time
    $When = { param($Value) try { if ($Value) { $(if ($Value -is [datetime]) { if ($Value.Kind -eq 'Local') { $Value.ToUniversalTime() } else { [datetime]::SpecifyKind($Value, 'Utc') } } else { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal,AdjustToUniversal') }).ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null } } catch { [string]$Value } }

    # --- tie records to addresses: tokens and Entra sessions from the sign-ins, mailbox sessions from the records ---
    $Tokens = @{}
    $EntraSessions = @{}
    foreach ($SignIn in @(@($SignIns) + @($NonInteractiveSignIns) | Where-Object { $_ })) {
        $IP = & $HostOf $SignIn.IPAddress
        if (-not $IP) { continue }
        if ($SignIn.UniqueTokenId) { $Tokens[[string]$SignIn.UniqueTokenId] = $IP }
        if ($SignIn.SessionId) {
            if (-not $EntraSessions.ContainsKey([string]$SignIn.SessionId)) { $EntraSessions[[string]$SignIn.SessionId] = [System.Collections.Generic.HashSet[string]]::new() }
            $null = $EntraSessions[[string]$SignIn.SessionId].Add($IP)
        }
    }
    $MailboxSessions = @{}
    foreach ($Record in @($MailRecords | Where-Object { $_ })) {
        $AD = $Record.AuditData
        $IP = & $HostOf ($AD.ClientIP ?? $AD.ClientIPAddress)
        if (-not $IP -or -not $AD.SessionId) { continue }
        if (-not $MailboxSessions.ContainsKey([string]$AD.SessionId)) { $MailboxSessions[[string]$AD.SessionId] = [System.Collections.Generic.HashSet[string]]::new() }
        $null = $MailboxSessions[[string]$AD.SessionId].Add($IP)
    }
    $Nearest = {
        param($Candidates)
        @($Candidates | Where-Object { $_.IP } | Sort-Object -Property @{ Expression = { $_.Order } }, @{ Expression = { $Rank[[string]$VerdictOf[$_.IP]] ?? 9 } }) | Select-Object -First 1
    }
    $Resolve = {
        param($AD)
        $Context = $AD.AppAccessContext
        $Candidates = [System.Collections.Generic.List[object]]::new()
        $RecordIP = & $HostOf ($AD.ClientIP ?? $AD.ClientIPAddress)
        if ($RecordIP) { $Candidates.Add([pscustomobject]@{ IP = $RecordIP; Source = 'record'; Order = 0 }) }
        if ($Context.UniqueTokenId -and $Tokens.ContainsKey([string]$Context.UniqueTokenId)) { $Candidates.Add([pscustomobject]@{ IP = $Tokens[[string]$Context.UniqueTokenId]; Source = 'token'; Order = 1 }) }
        if ($Context.AADSessionId -and $EntraSessions.ContainsKey([string]$Context.AADSessionId)) {
            foreach ($IP in $EntraSessions[[string]$Context.AADSessionId]) { $Candidates.Add([pscustomobject]@{ IP = $IP; Source = 'Entra session'; Order = 2 }) }
        }
        if ($AD.SessionId -and $MailboxSessions.ContainsKey([string]$AD.SessionId)) {
            foreach ($IP in $MailboxSessions[[string]$AD.SessionId]) { $Candidates.Add([pscustomobject]@{ IP = $IP; Source = 'mailbox session'; Order = 3 }) }
        }
        # a record whose own address is a Microsoft front end says nothing about the actor: prefer what it is tied to
        $Useful = @($Candidates | Where-Object { $VerdictOf[$_.IP] -and $VerdictOf[$_.IP] -ne 'Service' })
        $Pick = if ($Useful.Count -gt 0) { & $Nearest $Useful } else { $Candidates | Select-Object -First 1 }
        if (-not $Pick) { return [pscustomobject]@{ IP = $null; Source = 'none'; Verdict = $null } }
        [pscustomobject]@{ IP = $Pick.IP; Source = $Pick.Source; Verdict = $(if ($VerdictOf[$Pick.IP]) { $VerdictOf[$Pick.IP] } else { 'Unknown' }) }
    }
    $Props = { param($AD) @(@($AD.OperationProperties) + @($AD.Parameters) | Where-Object { $_ -and $_.Name } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ' }

    # --- mail: item-level rows from the records already read ---
    $MailRows = [System.Collections.Generic.List[object]]::new()
    $Unattributed = 0
    foreach ($Record in @($MailRecords | Where-Object { $_ -and $_.AuditData })) {
        $AD = $Record.AuditData
        $Address = & $Resolve $AD
        if (-not $Address.IP) { $Unattributed++; continue }
        if ($Address.Verdict -notin $AttackerSide) { continue }
        $Operation = [string]($AD.Operation ?? $Record.Operation)
        $AccessType = [string]($AD.MailAccessType ?? (@($AD.OperationProperties) | Where-Object { $_.Name -eq 'MailAccessType' } | Select-Object -First 1).Value)
        $Client = [string]($AD.ClientInfoString ?? $AD.AppAccessContext.ClientAppName)
        if ($Client.Length -gt 120) { $Client = $Client.Substring(0, 120) + '...' }
        $New = {
            param($Folder, $Subject, $MessageId, $Detail, $ItemCount)
            $MailRows.Add([pscustomobject]@{
                    When              = & $When $AD.CreationTime
                    Operation         = $Operation
                    AccessType        = $AccessType
                    Folder            = [string]$Folder
                    Subject           = [string]$Subject
                    InternetMessageId = [string]$MessageId
                    ItemCount         = $ItemCount
                    Detail            = [string]$Detail
                    IP                = $Address.IP
                    IPSource          = $Address.Source
                    IPVerdict         = $Address.Verdict
                    MailboxOwner      = [string]($AD.MailboxOwnerUPN ?? $UserPrincipalName)
                    LogonType         = $AD.LogonType
                    Client            = $Client
                    SessionId         = [string]$AD.SessionId
                })
        }
        switch ($Operation) {
            'MailItemsAccessed' {
                $Folders = @($AD.Folders | Where-Object { $_ })
                if ($Folders.Count -eq 0) { & $New $null $null $null (& $Props $AD) ([int]($AD.OperationCount ?? 1)); break }
                foreach ($Folder in $Folders) {
                    $Items = @($Folder.FolderItems | Where-Object { $_ })
                    if ($AccessType -eq 'Sync') {
                        & $New $Folder.Path '(whole folder synced to a desktop client)' $null $null $Items.Count
                    } else {
                        foreach ($Item in $Items) { & $New $Folder.Path $Item.Subject $Item.InternetMessageId $null 1 }
                        if ($Items.Count -eq 0) { & $New $Folder.Path $null $null $null 0 }
                    }
                }
            }
            { $_ -in @('SoftDelete', 'HardDelete', 'MoveToDeletedItems', 'Move', 'Copy') } {
                $Destination = if ($AD.DestFolder.Path) { "to $($AD.DestFolder.Path)" } else { $null }
                $Items = @($AD.AffectedItems | Where-Object { $_ })
                foreach ($Item in $Items) { & $New $Item.ParentFolder.Path $Item.Subject $Item.InternetMessageId $Destination 1 }
                if ($Items.Count -eq 0) { & $New $AD.Folder.Path $null $null $Destination 0 }
            }
            { $_ -in @('Send', 'SendAs', 'SendOnBehalf', 'AttachmentAccess') } {
                $Item = $AD.Item
                $Detail = if ($Item.Attachments) { "Attachments: $($Item.Attachments)" } else { & $Props $AD }
                & $New $Item.ParentFolder.Path $Item.Subject $Item.InternetMessageId $Detail 1
            }
            'UpdateFolderPermissions' {
                $Folder = $AD.Item.ParentFolder
                & $New $Folder.Path $null $null "$($Folder.MemberUpn): $($Folder.MemberRights)" 1
            }
            default { & $New $AD.Item.ParentFolder.Path $AD.Item.Subject $AD.Item.InternetMessageId (& $Props $AD) 1 }
        }
    }

    # name the opened messages that the records did not name
    $SubjectResult = [pscustomobject]@{ Resolved = 0; Unresolved = 0; Error = $null }
    $Unnamed = @($MailRows | Where-Object { $_.InternetMessageId -and -not $_.Subject } | ForEach-Object { $_.InternetMessageId } | Select-Object -Unique)
    if ($Unnamed.Count -gt 0) {
        $SubjectResult = Resolve-CIPPBecMessageSubjects -TenantFilter $TenantFilter -MessageIds $Unnamed -Known $KnownSubjects -LookbackDays ([int]($Cfg.subjectLookbackDays ?? 90)) -Anchor $Anchor
        foreach ($Row in $MailRows) {
            if ($Row.InternetMessageId -and -not $Row.Subject -and $SubjectResult.Subjects.ContainsKey($Row.InternetMessageId)) { $Row.Subject = $SubjectResult.Subjects[$Row.InternetMessageId] }
        }
    }
    $Count = { param($Ops) @($MailRows | Where-Object { $_.Operation -in $Ops }).Count }
    $MailSummary = [pscustomobject]@{
        Rows               = $MailRows.Count
        MessagesOpened     = @($MailRows | Where-Object { $_.Operation -eq 'MailItemsAccessed' -and $_.InternetMessageId } | ForEach-Object { $_.InternetMessageId } | Select-Object -Unique).Count
        FoldersSynced      = @($MailRows | Where-Object { $_.Operation -eq 'MailItemsAccessed' -and $_.AccessType -eq 'Sync' } | ForEach-Object { "$($_.MailboxOwner)|$($_.Folder)" } | Select-Object -Unique).Count
        Deleted            = & $Count @('SoftDelete', 'HardDelete', 'MoveToDeletedItems')
        Moved              = & $Count @('Move')
        Sent               = & $Count @('Send', 'SendAs', 'SendOnBehalf')
        AttachmentsRead    = & $Count @('AttachmentAccess')
        Searches           = & $Count @('SearchQueryInitiatedExchange')
        OtherMailboxes     = @($MailRows | Where-Object { $_.MailboxOwner -and $_.MailboxOwner -ne $UserPrincipalName } | ForEach-Object { $_.MailboxOwner } | Select-Object -Unique).Count
        Unattributed       = $Unattributed
        SubjectsResolved   = [int]$SubjectResult.Resolved
        SubjectsUnresolved = [int]$SubjectResult.Unresolved
    }
    $Mail = New-CIPPBecCollectorResult -Data @($MailRows | Sort-Object -Property When) -Error $SubjectResult.Error
    $Mail | Add-Member -NotePropertyName 'Summary' -NotePropertyValue $MailSummary -Force

    # --- files: one search for the attacker-side addresses ---
    $SideIPs = @($Verdicts | Where-Object { $_.Verdict -in $AttackerSide } | ForEach-Object { [string]$_.IP } | Select-Object -Unique)
    $Files = if ($SideIPs.Count -eq 0) {
        New-CIPPBecCollectorResult -Data @()
    } else {
        try {
            $FileRows = [System.Collections.Generic.List[object]]::new()
            $Complete = $true
            $Cap = $null
            for ($i = 0; $i -lt $SideIPs.Count; $i += 50) {
                $Chunk = @($SideIPs[$i..([Math]::Min($i + 49, $SideIPs.Count - 1))])
                $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations @($Cfg.fileOperations) -UserIds @($UserPrincipalName) -IPAddresses $Chunk -Anchor $Anchor -MaxPages $MaxPages
                if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
                foreach ($Record in @($Search.Records)) {
                    $AD = $Record.AuditData
                    if (-not $AD) { continue }
                    $Address = & $Resolve $AD
                    $FileRows.Add([pscustomobject]@{
                            When        = & $When $AD.CreationTime
                            Operation   = [string]$AD.Operation
                            File        = [string]$AD.SourceFileName
                            Url         = [string]$AD.ObjectId
                            Site        = [string]$AD.SiteUrl
                            Destination = if ($AD.DestinationFileName) { "$($AD.DestinationRelativeUrl)/$($AD.DestinationFileName)" } else { $null }
                            SearchQuery = [string]($AD.SearchQueryText ?? $AD.QueryText)
                            IP          = $Address.IP
                            IPSource    = $Address.Source
                            IPVerdict   = $Address.Verdict
                            UserAgent   = [string]$AD.UserAgent
                            App         = [string]($AD.ApplicationDisplayName ?? $AD.AppAccessContext.ClientAppName)
                        })
                }
            }
            $Result = New-CIPPBecCollectorResult -Data @($FileRows | Sort-Object -Property When) -Complete $Complete -Cap $Cap
            $Result | Add-Member -NotePropertyName 'Summary' -NotePropertyValue ([pscustomobject]@{
                    Files      = @($FileRows | ForEach-Object { $_.Url } | Where-Object { $_ } | Select-Object -Unique).Count
                    Downloaded = @($FileRows | Where-Object { $_.Operation -in @('FileDownloaded', 'FileSyncDownloadedFull') }).Count
                    Accessed   = @($FileRows | Where-Object { $_.Operation -in @('FileAccessed', 'FilePreviewed') }).Count
                    Uploaded   = @($FileRows | Where-Object { $_.Operation -eq 'FileUploaded' }).Count
                    Deleted    = @($FileRows | Where-Object { $_.Operation -in @('FileDeleted', 'FileRecycled') }).Count
                    Searches   = @($FileRows | Where-Object { $_.Operation -eq 'SearchQueryPerformed' }).Count
                }) -Force
            $Result
        } catch {
            New-CIPPBecCollectorResult -Data @() -Error "File activity search failed: $((Get-NormalizedError -message $_.Exception.Message))"
        }
    }

    # --- link usage: who opened the links created in the window ---
    $LinkItems = @($SharingChanges | ForEach-Object { [string]($_.ItemUrl ?? $_.ObjectId) } | Where-Object { $_ -match '^https?://' } | Select-Object -Unique)
    $LinkUsage = if ($LinkItems.Count -eq 0) {
        New-CIPPBecCollectorResult -Data @()
    } else {
        try {
            $UseRows = [System.Collections.Generic.List[object]]::new()
            $Complete = $true
            $Cap = $null
            for ($i = 0; $i -lt $LinkItems.Count; $i += 50) {
                $Chunk = @($LinkItems[$i..([Math]::Min($i + 49, $LinkItems.Count - 1))])
                $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations @($Cfg.linkUsageOperations) -ObjectIds $Chunk -Anchor $Anchor -MaxPages $MaxPages
                if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
                foreach ($Record in @($Search.Records)) {
                    $AD = $Record.AuditData
                    if (-not $AD) { continue }
                    $UseRows.Add([pscustomobject]@{
                            When      = & $When $AD.CreationTime
                            Operation = [string]$AD.Operation
                            File      = [string]$AD.SourceFileName
                            Url       = [string]$AD.ObjectId
                            OpenedBy  = [string]$AD.UserId
                            IP        = & $HostOf ($AD.ClientIP ?? $AD.ClientIPAddress)
                            UserAgent = [string]$AD.UserAgent
                        })
                }
            }
            New-CIPPBecCollectorResult -Data @($UseRows | Sort-Object -Property When) -Complete $Complete -Cap $Cap
        } catch {
            New-CIPPBecCollectorResult -Data @() -Error "Sharing-link usage search failed: $((Get-NormalizedError -message $_.Exception.Message))"
        }
    }

    # --- Microsoft Forms: everything the account did, and the reach of forms built from attacker addresses ---
    $Forms = try {
        $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -RecordType 'MicrosoftForms' -UserIds @($UserPrincipalName) -Anchor $Anchor -MaxPages $MaxPages
        $FormRows = @(foreach ($Record in @($Search.Records)) {
                $AD = $Record.AuditData
                if (-not $AD) { continue }
                $Address = & $Resolve $AD
                $Operation = [string]$AD.Operation
                [pscustomobject]@{
                    When      = & $When $AD.CreationTime
                    Operation = $Operation
                    FormName  = [string]$AD.FormName
                    FormId    = [string]($AD.FormId ?? $AD.ObjectId)
                    UserType  = [string]$AD.FormsUserType
                    IP        = $Address.IP
                    IPSource  = $Address.Source
                    IPVerdict = $Address.Verdict
                    Flagged   = [bool]($Address.Verdict -in $AttackerSide -and $Operation -in @($Cfg.formsAttackerOperations))
                    Detail    = & $Props $AD
                }
            })
        $FormSummaries = @(foreach ($FormId in @($FormRows | Where-Object { $_.Flagged -and $_.FormId } | ForEach-Object { $_.FormId } | Select-Object -Unique)) {
                $Reach = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations @($Cfg.formsResponseOperations) -FreeText $FormId -Anchor $Anchor -MaxPages $MaxPages
                $Records = @($Reach.Records | Where-Object { $_.AuditData -and [string]($_.AuditData.FormId ?? $_.AuditData.ObjectId) -eq $FormId })
                $Responses = @($Records | Where-Object { $_.AuditData.Operation -in @('CreateResponse', 'SubmitResponse') })
                [pscustomobject]@{
                    FormId             = $FormId
                    FormName           = ($FormRows | Where-Object { $_.FormId -eq $FormId -and $_.FormName } | Select-Object -First 1).FormName
                    Responses          = $Responses.Count
                    AnonymousResponses = @($Responses | Where-Object { -not $_.AuditData.ResponderId }).Count
                    Views              = @($Records | Where-Object { $_.AuditData.Operation -eq 'ViewRuntimeForm' }).Count
                    PhishingFlagged    = [bool](@($Records | Where-Object { $_.AuditData.Operation -eq 'UpdatePhishingStatus' }).Count)
                    Complete           = [bool]$Reach.Complete
                }
            })
        $Result = New-CIPPBecCollectorResult -Data @($FormRows | Sort-Object -Property When) -Complete ([bool]$Search.Complete) -Cap $Search.Cap
        $Result | Add-Member -NotePropertyName 'Summary' -NotePropertyValue ([pscustomobject]@{
                FlaggedActions = @($FormRows | Where-Object { $_.Flagged }).Count
                Forms          = @($FormSummaries)
            }) -Force
        $Result
    } catch {
        New-CIPPBecCollectorResult -Data @() -Error "Microsoft Forms search failed: $((Get-NormalizedError -message $_.Exception.Message))"
    }

    [pscustomobject]@{
        Mail      = $Mail
        Files     = $Files
        LinkUsage = $LinkUsage
        Forms     = $Forms
        Subjects  = $SubjectResult
    }
}
