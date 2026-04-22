function Get-CIPPQueueData {
    param($Request = $null, $TriggerMetadata = $null, $Reference = $null, $QueueId = $null)

    $QueueId = $Request.Query.QueueId ?? $QueueId
    $Reference = $Request.Query.Reference ?? $Reference

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
