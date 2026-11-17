function Update-CIPPOneDriveCopyToUserStatus {
    <#
    .SYNOPSIS
        Polls a OneDrive copy started by Start-CIPPOneDriveCopyToUser and returns per-recipient state.
    .DESCRIPTION
        Each copy job has its own state row in the OneDriveCopyToUser table, so a status call never has
        to poll everything. SharePoint bundles the submitted root items into one or more jobs (seen live:
        7 root items became 4 jobs) and does not say which items each job holds, so nothing here maps a
        job to a root item; each recipient has 1..RootItemCount jobs.
          - SharePoint is asked at most once per MinimumIntervalSeconds per operation. The check is
            claimed with an ETag-conditional update of the operation row, so only one call per window
            polls; every other call (inside the window, or losing the claim) returns the stored job
            states without calling SharePoint. The winner stops starting polls after three quarters of
            the window.
          - A check polls at most MaxJobsPerCheck unfinished jobs, least recently polled first, so
            every job is reached over successive checks however many there are.
        Jobs are polled with Get-CIPPSharePointCopyJobProgress, the library copy's parser; the library
        copy's own status code is not used or changed.

        A recipient's State is Queued, InProgress, Completed or Failed; Completed and Failed are final.
        Completed needs all of:
          - every one of its jobs polled and confirmed finished by SharePoint (JobState 0);
          - no errors, accumulated across checks;
          - every job processed something and at least as many objects as it expected;
          - at least as many files created across its jobs as were counted in the leaver's OneDrive at
            start (SourceFileCount).
        Fewer files than counted is Failed, because files may be missing. When every file is accounted
        for, a difference that cannot mean a missing file is a warning on a Completed copy, not a
        failure: more files than counted (added after the start), or bytes processed that differ from
        the bytes counted at start (SourceBytes; SharePoint can rewrite file metadata while copying).
        Live testing matched both totals exactly for plain files, Office files and OneNote notebooks.
        Anything else, once every job is final, is Failed. The operation's State is Completed only when
        every recipient is.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$OperationId,

        # Minimum time between two checks of SharePoint for one operation.
        [int]$MinimumIntervalSeconds = 60,

        # At most this many unfinished jobs are polled per check (about a second each), which keeps a
        # status call well inside the HTTP timeout.
        [int]$MaxJobsPerCheck = 100
    )

    $TableName = 'OneDriveCopyToUser'
    # A job whose progress cannot be read this many times in a row is given up as failed.
    $MaxPollFailures = 5
    $MaxMessagesPerJob = 25
    $MaxMessagesPerRecipient = 50
    $SaveEvery = 10

    if ($OperationId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw [System.ArgumentException]::new('OperationId is not a valid operation id.')
    }

    $Table = Get-CIPPTable -TableName $TableName
    # Rows are keyed by the tenant's customerId; copies started before that are under the raw
    # tenantFilter. Every row of one copy shares the partition its operation row was found in.
    $Operation = $null
    $PartitionKey = $null
    foreach ($ReadKey in (Get-CIPPOneDriveCopyTenantKey -TenantFilter $TenantFilter).ReadKeys) {
        $SafeKey = $ReadKey -replace "'", "''"
        $Operation = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeKey' and RowKey eq '$OperationId'") |
            Where-Object { $_.Kind -eq 'Operation' } | Select-Object -First 1
        if ($Operation) { $PartitionKey = $ReadKey; break }
    }
    if (-not $Operation) {
        throw [System.Management.Automation.ItemNotFoundException]::new('OneDrive copy operation not found.')
    }
    $SafeTenant = $PartitionKey -replace "'", "''"

    $Records = @()
    if ($Operation.Recipients) { $Records = @($Operation.Recipients | ConvertFrom-Json) }

    $ReadList = {
        param($Value)
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return @() }
        try { @([string]$Value | ConvertFrom-Json) } catch { @() }
    }
    $RootItemCount = [int]($Operation.RootItemCount ?? 0)
    # Totals counted in the leaver's OneDrive at start. A row without them (started before they were
    # recorded) can never be confirmed complete.
    $SourceFileCount = if ($null -ne $Operation.SourceFileCount) { [int64]$Operation.SourceFileCount } else { $null }
    $SourceBytes = if ($null -ne $Operation.SourceBytes) { [int64]$Operation.SourceBytes } else { $null }
    $IncludeVersionHistory = [bool]$Operation.IncludeVersionHistory
    # SharePoint bundles root items into jobs, so 1..RootItemCount jobs is expected. No jobs, or more
    # jobs than items submitted, is not something it has been seen to do and cannot be confirmed: such
    # a recipient is Failed and never polled. (Start-CIPPOneDriveCopyToUser already refuses these.)
    $JobCountValid = {
        param($Record)
        [int]$Record.JobCount -ge 1 -and ($RootItemCount -le 0 -or [int]$Record.JobCount -le $RootItemCount)
    }

    # --- Stored job states ------------------------------------------------------------------------
    $StatePrefix = "$OperationId-js-"
    $States = @{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey ge '$StatePrefix' and RowKey lt '$OperationId-js.'")) {
        if ($null -eq $Row -or $null -eq $Row.RecipientIndex -or $null -eq $Row.JobIndex) { continue }
        $States["$([int]$Row.RecipientIndex)-$([int]$Row.JobIndex)"] = [PSCustomObject]@{
            RecipientIndex       = [int]$Row.RecipientIndex
            JobIndex             = [int]$Row.JobIndex
            IsFinal              = [bool]$Row.IsFinal
            Failed               = [bool]$Row.Failed
            ObjectsProcessed     = [int64]($Row.ObjectsProcessed ?? 0)
            TotalExpectedObjects = $Row.TotalExpectedObjects
            FilesCreated         = [int64]($Row.FilesCreated ?? 0)
            BytesProcessed       = [int64]($Row.BytesProcessed ?? 0)
            TotalErrors          = [int64]($Row.TotalErrors ?? 0)
            TotalWarnings        = [int64]($Row.TotalWarnings ?? 0)
            ErrorMessages        = @(& $ReadList $Row.ErrorMessages)
            WarningMessages      = @(& $ReadList $Row.WarningMessages)
            PollFailures         = [int]($Row.PollFailures ?? 0)
            LastPolledUnix       = [int64]($Row.LastPolledUnix ?? 0)
        }
    }

    $NewState = {
        param([int]$RecipientIndex, [int]$JobIndex)
        [PSCustomObject]@{
            RecipientIndex = $RecipientIndex; JobIndex = $JobIndex; IsFinal = $false; Failed = $false
            ObjectsProcessed = 0; TotalExpectedObjects = $null; FilesCreated = 0; BytesProcessed = 0
            TotalErrors = 0; TotalWarnings = 0; ErrorMessages = @(); WarningMessages = @(); PollFailures = 0; LastPolledUnix = 0
        }
    }
    $AddMessages = {
        param([object[]]$Existing, [object[]]$New)
        $Seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $List = [System.Collections.Generic.List[string]]::new()
        foreach ($Message in @($Existing) + @($New)) {
            if ([string]::IsNullOrWhiteSpace([string]$Message)) { continue }
            if ($List.Count -ge $MaxMessagesPerJob) { break }
            if ($Seen.Add([string]$Message)) { $List.Add([string]$Message) }
        }
        @($List)
    }
    # Folds one progress reading into a job's stored state and decides whether the job is final.
    # Counts keep the highest value seen per job, and error messages accumulate. Each reading is the
    # last value the shared parser found in the logs it was given, and SharePoint's log queue is read,
    # not kept, so a later reading can carry fewer (or no) log lines than an earlier one. If the counts
    # are running totals (as observed: the final reading equalled the files and bytes in the source),
    # the highest seen is the latest. If they ever turned out to be per-reading increments, the highest
    # seen would undercount, and the totals check below would fail the recipient: licences are held,
    # never released early. Summing readings instead could double-count running totals and confirm a
    # copy that is short, which is the failure that must not happen.
    $MergeProgress = {
        param($State, $Progress)
        # The shared parser also calls a job complete when SharePoint's progress call failed (JobState
        # unknown, -1) but the job's queue log showed some progress. That only means the job was
        # running, so here a job may finish cleanly only on an explicit JobState 0 from SharePoint; a
        # reading that reports errors still fails it. Anything else counts as an unreadable check.
        $JobStateKnown = $null -ne $Progress.JobState -and [int]$Progress.JobState -eq 0
        $ReportsErrors = [int64]($Progress.TotalErrors ?? 0) -gt 0 -or @($Progress.ErrorMessages | Where-Object { $_ }).Count -gt 0
        $Unconfirmed = $Progress.IsComplete -and -not $JobStateKnown -and -not $ReportsErrors
        if ($Unconfirmed) { $State.PollFailures++ } else { $State.PollFailures = 0 }
        $State.ObjectsProcessed = [Math]::Max([int64]$State.ObjectsProcessed, [int64]($Progress.ObjectsProcessed ?? 0))
        if ($null -ne $Progress.TotalExpectedObjects) { $State.TotalExpectedObjects = [int64]$Progress.TotalExpectedObjects }
        $State.FilesCreated = [Math]::Max([int64]$State.FilesCreated, [int64]($Progress.FilesCreated ?? 0))
        $State.BytesProcessed = [Math]::Max([int64]$State.BytesProcessed, [int64]($Progress.BytesProcessed ?? 0))
        $State.TotalErrors = [Math]::Max([int64]$State.TotalErrors, [int64]($Progress.TotalErrors ?? 0))
        $State.TotalWarnings = [Math]::Max([int64]$State.TotalWarnings, [int64]($Progress.TotalWarnings ?? 0))
        $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages $Progress.ErrorMessages)
        $State.WarningMessages = @(& $AddMessages $State.WarningMessages $Progress.WarningMessages)
        if ($Unconfirmed) {
            if ($State.PollFailures -ge $MaxPollFailures) {
                $State.IsFinal = $true
                $State.Failed = $true
                $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages @("SharePoint did not confirm the copy job finished after $MaxPollFailures checks in a row."))
            }
        } elseif ($Progress.IsComplete) {
            $State.IsFinal = $true
            $State.Failed = $State.TotalErrors -gt 0 -or $State.ErrorMessages.Count -gt 0
            # A finished job always processes something: even an empty folder or a 0-byte file reports
            # objects processed (seen live: 2 of 2). Nothing processed means nothing was copied.
            if ($State.ObjectsProcessed -le 0) {
                $State.Failed = $true
                $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages @('The copy job finished without copying anything.'))
            } elseif ($null -eq $State.TotalExpectedObjects) {
                $State.Failed = $true
                $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages @('The copy job finished without reporting how many objects it expected to copy.'))
            } elseif ($State.ObjectsProcessed -lt [int64]$State.TotalExpectedObjects) {
                $State.Failed = $true
                $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages @("The copy job finished having processed $($State.ObjectsProcessed) of $($State.TotalExpectedObjects) objects."))
            }
        }
    }

    # --- Check SharePoint, rate limited -----------------------------------------------------------
    $Now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $LastChecked = [int64]($Operation.LastCheckedUnix ?? 0)
    $Polled = 0
    $CheckedSharePoint = $false
    $Claimed = $false
    if ($Now - $LastChecked -ge $MinimumIntervalSeconds) {
        # Claim the check with an ETag-conditional update of the operation row (Update-CIPPAzDataTableEntity
        # without -Force sends If-Match). Of several calls that read the same row, exactly one wins; the
        # others get a precondition failure and return the stored state without polling, so two calls
        # never poll and overwrite the same jobs. Any failure, and a row read without an ETag, counts as
        # not claimed (fail closed). Losing only delays a check: the winner moves LastCheckedUnix on, and
        # the first call after the next window claims again.
        $ETag = $Operation.ETag
        if ($null -ne $ETag -and -not [string]::IsNullOrWhiteSpace([string]$ETag)) {
            try {
                Update-CIPPAzDataTableEntity @Table -Entity ([PSCustomObject]@{
                        PartitionKey    = $PartitionKey
                        RowKey          = $OperationId
                        ETag            = $ETag
                        LastCheckedUnix = $Now
                    })
                $Claimed = $true
            } catch {
                Write-Information "OneDrive copy $OperationId status: another check holds this window ($($_.Exception.Message))"
            }
        } else {
            Write-Information "OneDrive copy $OperationId status: operation row has no ETag; not checking SharePoint"
        }
    }
    if ($Claimed) {
        $CheckedSharePoint = $true
        $LastChecked = $Now
        # The winner stops starting new polls before the window ends, so the next window's winner never
        # polls the same jobs while this call is still writing them.
        $PollBudgetSeconds = if ($MinimumIntervalSeconds -gt 0) { [Math]::Max(1.0, $MinimumIntervalSeconds * 0.75) } else { [double]::MaxValue }
        $PollClock = [System.Diagnostics.Stopwatch]::StartNew()

        $Candidates = foreach ($Record in $Records) {
            if ($Record.StartError -or -not (& $JobCountValid $Record)) { continue }
            for ($j = 0; $j -lt [int]$Record.JobCount; $j++) {
                $State = $States["$([int]$Record.Index)-$j"]
                if ($State -and $State.IsFinal) { continue }
                [PSCustomObject]@{ Record = $Record; JobIndex = $j; LastPolledUnix = if ($State) { $State.LastPolledUnix } else { 0 } }
            }
        }
        $Selected = @($Candidates | Sort-Object LastPolledUnix, { [int]$_.Record.Index }, JobIndex | Select-Object -First $MaxJobsPerCheck)

        $Changed = [System.Collections.Generic.List[object]]::new()
        foreach ($Group in @($Selected | Group-Object { [int]$_.Record.Index })) {
            if ($PollClock.Elapsed.TotalSeconds -ge $PollBudgetSeconds) { break }
            $Record = $Group.Group[0].Record
            $Sub = Get-CIPPSharePointLibraryCopyOperation -TenantFilter $PartitionKey -OperationId $Record.SubOperationId -TableName $TableName
            if (-not $Sub) {
                throw [System.Management.Automation.ItemNotFoundException]::new("Copy jobs for $($Record.UserPrincipalName) not found.")
            }
            foreach ($Candidate in $Group.Group) {
                if ($PollClock.Elapsed.TotalSeconds -ge $PollBudgetSeconds) { break }
                $Key = "$([int]$Record.Index)-$($Candidate.JobIndex)"
                $State = $States[$Key] ?? (& $NewState ([int]$Record.Index) $Candidate.JobIndex)
                $Handle = @($Sub.CopyJobInfos)[$Candidate.JobIndex]
                if ($null -eq $Handle) {
                    $State.IsFinal = $true
                    $State.Failed = $true
                    $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages @('The stored copy job could not be found.'))
                } else {
                    try {
                        $Progress = Get-CIPPSharePointCopyJobProgress -TenantFilter $TenantFilter -SourceSiteUrl $Sub.SourceSiteUrl -CopyJobInfo $Handle
                        & $MergeProgress $State $Progress
                    } catch {
                        $Detail = [regex]::Replace([string]$_.Exception.Message, 'https?://[^\s''"]+', '[url redacted]', 'IgnoreCase')
                        $Detail = ($Detail -replace '\s{2,}', ' ').Trim()
                        if ($Detail.Length -gt 280) { $Detail = $Detail.Substring(0, 280).Trim() + '…' }
                        $State.PollFailures++
                        if ($State.PollFailures -ge $MaxPollFailures) {
                            $State.IsFinal = $true
                            $State.Failed = $true
                            $State.ErrorMessages = @(& $AddMessages $State.ErrorMessages @("Progress could not be read $MaxPollFailures times in a row: $Detail"))
                        }
                    }
                }
                $State.LastPolledUnix = $Now
                $States[$Key] = $State
                $Polled++
                $StateRowKey = '{0}{1}-{2:D4}' -f $StatePrefix, $State.RecipientIndex, $State.JobIndex
                $Changed.Add(@{
                        PartitionKey     = $PartitionKey
                        RowKey           = $StateRowKey
                        RecipientIndex   = $State.RecipientIndex
                        JobIndex         = $State.JobIndex
                        IsFinal          = [bool]$State.IsFinal
                        Failed           = [bool]$State.Failed
                        ObjectsProcessed = [int64]$State.ObjectsProcessed
                        TotalExpectedObjects = if ($null -ne $State.TotalExpectedObjects) { [int64]$State.TotalExpectedObjects } else { $null }
                        FilesCreated     = [int64]$State.FilesCreated
                        BytesProcessed   = [int64]$State.BytesProcessed
                        TotalErrors      = [int64]$State.TotalErrors
                        TotalWarnings    = [int64]$State.TotalWarnings
                        ErrorMessages    = (ConvertTo-Json -InputObject @($State.ErrorMessages) -Compress)
                        WarningMessages  = (ConvertTo-Json -InputObject @($State.WarningMessages) -Compress)
                        PollFailures     = [int]$State.PollFailures
                        LastPolledUnix   = [int64]$State.LastPolledUnix
                    })
                # Saved in small batches, not once at the end: a check cut short (timeout, worker
                # recycle, an error further on) must keep what it already read, because SharePoint's
                # log queue does not give the same errors back, and the next check must move on to
                # other jobs rather than poll the same ones again.
                if ($Changed.Count -ge $SaveEvery) {
                    Add-CIPPAzDataTableEntity @Table -Entity @($Changed) -Force
                    $Changed.Clear()
                }
            }
        }
        if ($Changed.Count -gt 0) {
            Add-CIPPAzDataTableEntity @Table -Entity @($Changed) -Force
        }
    }

    # --- Per-recipient and overall state ----------------------------------------------------------
    $Results = foreach ($Record in $Records) {
        $Entry = [ordered]@{
            UserPrincipalName    = $Record.UserPrincipalName
            FolderName           = $Record.FolderName
            State                = 'Queued'
            IsComplete           = $false
            JobsComplete         = 0
            JobsTotal            = [int]$Record.JobCount
            ItemsCopied          = 0
            ObjectsProcessed     = 0
            TotalExpectedObjects = $null
            BytesCopied          = 0
            ErrorCount           = 0
            Errors               = @()
            Warnings             = @()
            Message              = 'Copy queued.'
        }

        if ($Record.StartError) {
            $Entry.State = 'Failed'
            $Entry.IsComplete = $true
            $Entry.ErrorCount = 1
            $Entry.Errors = @([string]$Record.StartError)
            $Entry.Message = [string]$Record.StartError
            [PSCustomObject]$Entry
            continue
        }

        $JobStates = @(for ($j = 0; $j -lt $Entry.JobsTotal; $j++) { $States["$([int]$Record.Index)-$j"] })
        $Known = @($JobStates | Where-Object { $_ })
        $FailedJobs = @($Known | Where-Object { $_.Failed })
        $Entry.JobsComplete = @($Known | Where-Object { $_.IsFinal }).Count
        $Entry.ItemsCopied = [int64](($Known | ForEach-Object { $_.FilesCreated } | Measure-Object -Sum).Sum)
        $Entry.ObjectsProcessed = [int64](($Known | ForEach-Object { $_.ObjectsProcessed } | Measure-Object -Sum).Sum)
        $Expected = @($Known | Where-Object { $null -ne $_.TotalExpectedObjects } | ForEach-Object { [int64]$_.TotalExpectedObjects })
        $Entry.TotalExpectedObjects = if ($Expected.Count -gt 0) { [int64](($Expected | Measure-Object -Sum).Sum) } else { $null }
        $Entry.BytesCopied = [int64](($Known | ForEach-Object { $_.BytesProcessed } | Measure-Object -Sum).Sum)
        $Entry.ErrorCount = [int64](($Known | ForEach-Object { [Math]::Max([int64]$_.TotalErrors, [int64]($_.Failed -and $_.TotalErrors -eq 0)) } | Measure-Object -Sum).Sum)
        $Entry.Errors = @($Known | ForEach-Object { $_.ErrorMessages } | Where-Object { $_ } | Select-Object -Unique | Select-Object -First $MaxMessagesPerRecipient)
        $Entry.Warnings = @($Known | ForEach-Object { $_.WarningMessages } | Where-Object { $_ } | Select-Object -Unique | Select-Object -First $MaxMessagesPerRecipient)

        # Totals are only compared once every job is final: before that they are partial by design.
        $AllJobsDone = $Entry.JobsTotal -gt 0 -and $Known.Count -eq $Entry.JobsTotal -and $Entry.JobsComplete -eq $Entry.JobsTotal
        $Shortfall = $null
        $TotalsWarnings = [System.Collections.Generic.List[string]]::new()
        if ($AllJobsDone -and $FailedJobs.Count -eq 0) {
            if ($Entry.ErrorCount -gt 0) {
                $Shortfall = "Copy finished, but SharePoint reported $($Entry.ErrorCount) error(s)."
            } elseif ($null -eq $SourceFileCount -or $null -eq $SourceBytes) {
                $Shortfall = 'The number of files and bytes to copy was not recorded when the copy started, so it cannot be confirmed complete.'
            } elseif ($Entry.ItemsCopied -lt $SourceFileCount) {
                # Fewer files than the leaver's OneDrive held means files may be missing: never Completed.
                $Shortfall = "Copy finished, but copied $($Entry.ItemsCopied) of $SourceFileCount files."
            } else {
                # Every file is accounted for. A difference that cannot mean a missing file is reported
                # as a warning instead of failing the copy (and holding the licences) for good:
                # - more files than counted: something was added to the leaver's OneDrive after the start;
                # - other bytes than counted: SharePoint can rewrite file metadata while copying.
                if ($Entry.ItemsCopied -gt $SourceFileCount) {
                    $TotalsWarnings.Add("Copied $($Entry.ItemsCopied) files, more than the $SourceFileCount counted when the copy started (files may have been added since).")
                }
                if ($IncludeVersionHistory -and $Entry.BytesCopied -lt $SourceBytes) {
                    $TotalsWarnings.Add("Copied $($Entry.BytesCopied) bytes with version history, less than the $SourceBytes bytes of current versions counted when the copy started.")
                } elseif (-not $IncludeVersionHistory -and $Entry.BytesCopied -ne $SourceBytes) {
                    $TotalsWarnings.Add("Copied $($Entry.BytesCopied) bytes; $SourceBytes bytes were counted when the copy started (SharePoint can change file sizes slightly while copying metadata).")
                }
            }
        }
        if (-not (& $JobCountValid $Record)) {
            $Entry.State = 'Failed'
            $Entry.IsComplete = $true
            if ($Entry.ErrorCount -lt 1) { $Entry.ErrorCount = 1 }
            $Entry.Message = "SharePoint has $($Entry.JobsTotal) copy job(s) for $RootItemCount root item(s); the copy cannot be confirmed complete."
            $Entry.Errors = @(@($Entry.Message) + @($Entry.Errors))
        } elseif ($AllJobsDone -and $FailedJobs.Count -eq 0 -and -not $Shortfall) {
            $Entry.State = 'Completed'
            $Entry.IsComplete = $true
            if ($TotalsWarnings.Count -gt 0) {
                $Entry.Message = "Copy completed with warnings: $($TotalsWarnings -join ' ')"
                $Entry.Warnings = @(@($TotalsWarnings) + @($Entry.Warnings))
            } else {
                $Entry.Message = 'Copy completed.'
            }
        } elseif ($AllJobsDone -and $FailedJobs.Count -eq 0) {
            $Entry.State = 'Failed'
            $Entry.IsComplete = $true
            if ($Entry.ErrorCount -lt 1) { $Entry.ErrorCount = 1 }
            $Entry.Message = $Shortfall
            $Entry.Errors = @(@($Shortfall) + @($Entry.Errors))
        } elseif ($AllJobsDone) {
            $Entry.State = 'Failed'
            $Entry.IsComplete = $true
            if ($Entry.ErrorCount -lt 1) { $Entry.ErrorCount = 1 }
            $Entry.Message = "Copy finished, but $($FailedJobs.Count) of $($Entry.JobsTotal) copy job(s) failed; some items were not copied."
        } elseif ($Entry.JobsComplete -eq 0 -and $Entry.ObjectsProcessed -eq 0) {
            $Entry.State = 'Queued'
            $Entry.Message = 'Copy queued.'
        } else {
            $Entry.State = 'InProgress'
            $Entry.Message = "Copy in progress ($($Entry.JobsComplete) of $($Entry.JobsTotal) copy jobs done)."
        }
        [PSCustomObject]$Entry
    }
    $Results = @($Results)

    $RecipientStates = @($Results | ForEach-Object { $_.State })
    $State = if ($RecipientStates.Count -gt 0 -and @($RecipientStates | Where-Object { $_ -ne 'Completed' }).Count -eq 0) { 'Completed' }
    elseif ($RecipientStates.Count -gt 0 -and @($RecipientStates | Where-Object { $_ -notin @('Completed', 'Failed') }).Count -eq 0) { 'Failed' }
    elseif (@($RecipientStates | Where-Object { $_ -ne 'Queued' }).Count -eq 0) { 'Queued' }
    else { 'InProgress' }

    $Message = switch ($State) {
        'Completed' { 'Copy completed for every recipient.' }
        'Failed' { 'Copy finished, but failed for at least one recipient. Do not remove licences until the failures are resolved.' }
        'Queued' { 'Copy queued.' }
        default { 'Copy in progress.' }
    }

    [PSCustomObject]@{
        OperationId       = $OperationId
        Leaver            = $Operation.LeaverUPN
        StartedBy         = $Operation.StartedBy
        StartedUtc        = $Operation.StartedUtc
        State             = $State
        IsComplete        = $State -in @('Completed', 'Failed')
        AllCompleted      = $State -eq 'Completed'
        RootItemCount     = [int]$Operation.RootItemCount
        SourceFileCount   = $SourceFileCount
        SourceBytes       = $SourceBytes
        ExpectedBytes     = [int64]($Operation.ExpectedBytes ?? 0)
        Recipients        = $Results
        CheckedSharePoint = $CheckedSharePoint
        JobsPolled        = $Polled
        LastCheckedUtc    = if ($LastChecked -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($LastChecked).UtcDateTime.ToString('o') } else { $null }
        NextCheckAfterUtc = if ($LastChecked -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($LastChecked + $MinimumIntervalSeconds).UtcDateTime.ToString('o') } else { $null }
        LastUpdatedUtc    = ([DateTime]::UtcNow).ToString('o')
        Message           = $Message
    }
}
