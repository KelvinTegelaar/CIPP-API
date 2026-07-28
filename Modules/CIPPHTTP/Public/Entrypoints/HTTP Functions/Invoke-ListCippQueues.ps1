function Invoke-ListCippQueues {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Lists several CIPP background queues at once and rolls them up into a single progress
        figure. ListCippQueue reports one queue; this exists for the actions that start several
        at a time - syncing a report that is compiled from more than one cache, for instance -
        where the useful answer is "how far along is the refresh" rather than the state of each
        individual queue.

        Pass QueueIds as a comma-separated list. Each is resolved through Get-CIPPQueueData, so
        the same data shape and status derivation applies as for a single queue. Ids that no
        longer exist are reported in MissingQueueIds rather than silently dropped, because a
        caller polling for completion needs to know the difference between a queue that finished
        and one that was never found.

        The rolled-up Status is the least complete state across the set: anything still running
        keeps the whole refresh Running, and a failure anywhere is surfaced rather than averaged
        away.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message 'Accessed this API' -Sev 'Debug'

    $RawIds = $Request.Query.QueueIds ?? $Request.Body.QueueIds
    $QueueIds = @($RawIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    if ($QueueIds.Count -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = 'QueueIds is required.' }
            })
    }

    $Queues = [System.Collections.Generic.List[object]]::new()
    $MissingQueueIds = [System.Collections.Generic.List[string]]::new()
    foreach ($QueueId in $QueueIds) {
        try {
            $Queue = @(Get-CIPPQueueData -QueueId $QueueId) | Where-Object { $_ } | Select-Object -First 1
            if ($Queue) { $Queues.Add($Queue) } else { $MissingQueueIds.Add($QueueId) }
        } catch {
            Write-Information "ListCippQueues: could not read queue $QueueId : $($_.Exception.Message)"
            $MissingQueueIds.Add($QueueId)
        }
    }

    # Task totals across every queue, so the progress bar reflects real work rather than an
    # average of percentages (queues differ wildly in size - a permission scan is a handful of
    # batches, a sharing link scan is one activity per site).
    $TotalTasks = 0; $CompletedTasks = 0; $RunningTasks = 0; $FailedTasks = 0
    $CompletedQueues = 0; $RunningQueues = 0; $FailedQueues = 0
    foreach ($Queue in $Queues) {
        $TotalTasks += [int]($Queue.TotalTasks ?? 0)
        $CompletedTasks += [int]($Queue.CompletedTasks ?? 0)
        $RunningTasks += [int]($Queue.RunningTasks ?? 0)
        $FailedTasks += [int]($Queue.FailedTasks ?? 0)

        switch ([string]$Queue.Status) {
            'Completed' { $CompletedQueues++ }
            'Completed (with errors)' { $CompletedQueues++; $FailedQueues++ }
            'Failed' { $FailedQueues++ }
            default { $RunningQueues++ }
        }
    }

    # A queue that was not found is treated as finished: it has either aged out of the window
    # or never started, and either way polling it forever would hang the caller.
    $AllFinished = $RunningQueues -eq 0
    $Status = if (-not $AllFinished) {
        'Running'
    } elseif ($FailedQueues -gt 0) {
        'Completed (with errors)'
    } elseif ($Queues.Count -eq 0) {
        'Not found'
    } else {
        'Completed'
    }

    $Body = [PSCustomObject]@{
        Queues          = @($Queues)
        MissingQueueIds = @($MissingQueueIds)
        Summary         = [PSCustomObject]@{
            TotalQueues     = $QueueIds.Count
            FoundQueues     = $Queues.Count
            CompletedQueues = $CompletedQueues
            RunningQueues   = $RunningQueues
            FailedQueues    = $FailedQueues
            TotalTasks      = $TotalTasks
            CompletedTasks  = $CompletedTasks
            RunningTasks    = $RunningTasks
            FailedTasks     = $FailedTasks
            PercentComplete = if ($TotalTasks -gt 0) { [math]::Round((($CompletedTasks / $TotalTasks) * 100), 1) } else { 0 }
            IsComplete      = $AllFinished
            Status          = $Status
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
