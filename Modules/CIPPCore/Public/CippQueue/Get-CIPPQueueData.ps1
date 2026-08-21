function Get-CIPPQueueData {
    param($Request = $null, $TriggerMetadata = $null, $Reference = $null, $QueueId = $null)

    $QueueId = $Request.Query.QueueId ?? $QueueId
    $Reference = $Request.Query.Reference ?? $Reference

    if ($env:CIPPNG -eq 'true') {
        $json = [Craft.Services.QueueStatusBridge]::GetRunStatus($Reference, $QueueId)
        $Entries = @($json | ConvertFrom-Json)

        # One logical operation can span several orchestrator runs carrying the same QueueId
        # suffix: activities re-queue continuation runs (timebox and throttle resumes) and
        # dispatch child orchestrations. A caller asking after one queue needs the roll-up of
        # the whole chain, not whichever run the bridge listed first - above all, a progress
        # tracker must keep polling while ANY chained run is still active, where reading just
        # the original run reports Completed the moment its own tasks finish.
        if (($QueueId -or $Reference) -and $Entries.Count -gt 1) {
            $Terminal = @('Completed', 'Failed', 'Completed (with errors)', 'Not found')
            $TotalTasks = 0; $CompletedTasks = 0; $RunningTasks = 0; $FailedTasks = 0
            $AnyActive = $false; $AnyFailed = $false
            $AllTasks = [System.Collections.Generic.List[object]]::new()
            foreach ($Entry in $Entries) {
                $TotalTasks += [int]($Entry.TotalTasks ?? 0)
                $CompletedTasks += [int]($Entry.CompletedTasks ?? 0)
                $RunningTasks += [int]($Entry.RunningTasks ?? 0)
                $FailedTasks += [int]($Entry.FailedTasks ?? 0)
                if ([string]$Entry.Status -notin $Terminal) { $AnyActive = $true }
                if ([string]$Entry.Status -in @('Failed', 'Completed (with errors)') -or [int]($Entry.FailedTasks ?? 0) -gt 0) { $AnyFailed = $true }
                foreach ($Task in @($Entry.Tasks)) { $AllTasks.Add($Task) }
            }
            $Rollup = $Entries[0].PSObject.Copy()
            $Rollup.TotalTasks = [Math]::Max($TotalTasks, 1)
            $Rollup.CompletedTasks = $CompletedTasks
            $Rollup.RunningTasks = $RunningTasks
            $Rollup.FailedTasks = $FailedTasks
            $Rollup.PercentComplete = [math]::Round((($CompletedTasks / [Math]::Max($TotalTasks, 1)) * 100), 1)
            $Rollup.Tasks = @($AllTasks)
            $Rollup.Status = if ($AnyActive) { 'Running' } elseif ($AnyFailed) { 'Completed (with errors)' } else { 'Completed' }
            return $Rollup
        }
        return $Entries
    }

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    $3HoursAgo = (Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ')

    if ($QueueId) {
        $SafeQueueId = ConvertTo-CIPPODataFilterValue -Value $QueueId -Type String
        $Filter = "PartitionKey eq 'CippQueue' and RowKey eq '$SafeQueueId'"
    } elseif ($Reference) {
        $SafeReference = ConvertTo-CIPPODataFilterValue -Value $Reference -Type String
        $Filter = "PartitionKey eq 'CippQueue' and Reference eq '$SafeReference' and Timestamp ge datetime'$3HoursAgo'"
    } else {
        $Filter = "PartitionKey eq 'CippQueue' and Timestamp ge datetime'$3HoursAgo'"
    }

    $CippQueueData = Get-CIPPAzDataTableEntity @CippQueue -Filter $Filter | Sort-Object -Property Timestamp -Descending

    $QueueData = foreach ($Queue in $CippQueueData) {
        $Tasks = Get-CIPPAzDataTableEntity @CippQueueTasks -Filter "PartitionKey eq 'Task' and QueueId eq '$($Queue.RowKey)'" | Where-Object { $_.Name } | Select-Object @{n = 'Timestamp'; exp = { $_.Timestamp } }, Name, Status
        $TaskStatus = @{}
        $Tasks | Group-Object -Property Status | ForEach-Object {
            $TaskStatus.$($_.Name) = $_.Count
        }

        if ($Tasks) {
            if ($Tasks.Status -notcontains 'Running' -and ($TaskStatus.Completed + $TaskStatus.Failed) -ge $Queue.TotalTasks) {
                if ($Tasks.Status -notcontains 'Failed') {
                    $Queue.Status = 'Completed'
                } else {
                    $Queue.Status = 'Completed (with errors)'
                }
            } else {
                $Queue.Status = 'Running'
            }
        }

        $TotalCompleted = $TaskStatus.Completed ?? 0
        $TotalFailed = $TaskStatus.Failed ?? 0
        $TotalRunning = $TaskStatus.Running ?? 0
        if ($Queue.TotalTasks -eq 0) { $Queue.TotalTasks = 1 }

        [PSCustomObject]@{
            PartitionKey    = $Queue.PartitionKey
            RowKey          = $Queue.RowKey
            Name            = $Queue.Name
            Link            = $Queue.Link
            Reference       = $Queue.Reference
            TotalTasks      = $Queue.TotalTasks
            CompletedTasks  = $TotalCompleted + $TotalFailed
            RunningTasks    = $TotalRunning
            FailedTasks     = $TotalFailed
            PercentComplete = [math]::Round(((($TotalCompleted + $TotalFailed) / $Queue.TotalTasks) * 100), 1)
            PercentFailed   = [math]::Round((($TotalFailed / $Queue.TotalTasks) * 100), 1)
            PercentRunning  = [math]::Round((($TotalRunning / $Queue.TotalTasks) * 100), 1)
            Tasks           = @($Tasks | Sort-Object -Descending Timestamp)
            Status          = $Queue.Status
            Timestamp       = $Queue.Timestamp
        }

    }

    return $QueueData
}
