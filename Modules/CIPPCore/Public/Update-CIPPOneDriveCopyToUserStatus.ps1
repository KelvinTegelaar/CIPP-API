function Update-CIPPOneDriveCopyToUserStatus {
    <#
    .SYNOPSIS
        Polls a OneDrive copy started by Start-CIPPOneDriveCopyToUser and returns per-recipient state.
    .DESCRIPTION
        SharePoint is asked at most once per MinimumIntervalSeconds per operation (claimed with an ETag-conditional
        update, so one caller polls per window) and for at most MaxJobsPerCheck unfinished jobs, least recently polled first.
        A recipient is Completed only when every job finished cleanly (JobState 0) and at least SourceFileCount files were
        created; fewer files is Failed. Completed and Failed are final.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$OperationId,

        [int]$MinimumIntervalSeconds = 60,

        # About a second per job, which keeps a status call well inside the HTTP timeout.
        [int]$MaxJobsPerCheck = 100
    )

    $TableName = 'OneDriveCopyToUser'
    $MaxPollFailures = 5
    $MaxMessagesPerJob = 25
    $MaxMessagesPerRecipient = 50
    $SaveEvery = 10

    if ($OperationId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw [System.ArgumentException]::new('OperationId is not a valid operation id.')
    }

    $Table = Get-CIPPTable -TableName $TableName
    $PartitionKey = Get-CIPPOneDriveCopyTenantKey -TenantFilter $TenantFilter
    $SafeTenant = $PartitionKey -replace "'", "''"
    $Operation = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$OperationId'").Where({ $_.Kind -eq 'Operation' }, 'First')[0]
    if (-not $Operation) {
        throw [System.Management.Automation.ItemNotFoundException]::new('OneDrive copy operation not found.')
    }

    $Records = @()
    if ($Operation.Recipients) { $Records = @($Operation.Recipients | ConvertFrom-Json) }

    $ReadList = {
        param($Value)
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { return @() }
        try { @([string]$Value | ConvertFrom-Json) } catch { @() }
    }
    $RootItemCount = [int]($Operation.RootItemCount ?? 0)
    $SourceFileCount = if ($null -ne $Operation.SourceFileCount) { [int64]$Operation.SourceFileCount } else { $null }
    $SourceBytes = if ($null -ne $Operation.SourceBytes) { [int64]$Operation.SourceBytes } else { $null }
    $IncludeVersionHistory = [bool]$Operation.IncludeVersionHistory
    # SharePoint bundles root items into 1..RootItemCount jobs; anything else cannot be confirmed.
    $JobCountValid = {
        param($Record)
        [int]$Record.JobCount -ge 1 -and ($RootItemCount -le 0 -or [int]$Record.JobCount -le $RootItemCount)
    }

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
    # Keeps the highest count seen per job: readings are running totals, and summing them could confirm a short copy.
    $MergeProgress = {
        param($State, $Progress)
        # The shared parser also calls a job complete on JobState -1 with some progress; only an explicit 0 counts here.
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
            # Even an empty folder or a 0-byte file reports objects processed.
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

    $Now = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $LastChecked = [int64]($Operation.LastCheckedUnix ?? 0)
    $Polled = 0
    $CheckedSharePoint = $false
    $Claimed = $false
    if ($Now - $LastChecked -ge $MinimumIntervalSeconds) {
        # Without -Force this sends If-Match, so exactly one of several concurrent callers wins the window.
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
        # Stop before the window ends so the next window's winner never polls jobs this call is still writing.
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
        $Sorted = @($Candidates | Sort-Object LastPolledUnix, { [int]$_.Record.Index }, JobIndex)
        $Selected = @(if ($Sorted.Count -gt $MaxJobsPerCheck) { $Sorted[0..($MaxJobsPerCheck - 1)] } else { $Sorted })

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
                # Saved in batches: SharePoint's log queue does not give the same errors back to a check cut short.
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
        $Errors = @($Known | ForEach-Object { $_.ErrorMessages } | Where-Object { $_ } | Select-Object -Unique)
        $Entry.Errors = @(if ($Errors.Count -gt $MaxMessagesPerRecipient) { $Errors[0..($MaxMessagesPerRecipient - 1)] } else { $Errors })
        $Warnings = @($Known | ForEach-Object { $_.WarningMessages } | Where-Object { $_ } | Select-Object -Unique)
        $Entry.Warnings = @(if ($Warnings.Count -gt $MaxMessagesPerRecipient) { $Warnings[0..($MaxMessagesPerRecipient - 1)] } else { $Warnings })

        $AllJobsDone = $Entry.JobsTotal -gt 0 -and $Known.Count -eq $Entry.JobsTotal -and $Entry.JobsComplete -eq $Entry.JobsTotal
        $Shortfall = $null
        $TotalsWarnings = [System.Collections.Generic.List[string]]::new()
        if ($AllJobsDone -and $FailedJobs.Count -eq 0) {
            if ($Entry.ErrorCount -gt 0) {
                $Shortfall = "Copy finished, but SharePoint reported $($Entry.ErrorCount) error(s)."
            } elseif ($null -eq $SourceFileCount -or $null -eq $SourceBytes) {
                $Shortfall = 'The number of files and bytes to copy was not recorded when the copy started, so it cannot be confirmed complete.'
            } elseif ($Entry.ItemsCopied -lt $SourceFileCount) {
                $Shortfall = "Copy finished, but copied $($Entry.ItemsCopied) of $SourceFileCount files."
            } else {
                # Every file is accounted for, so extra files or changed bytes are warnings, not failures.
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
