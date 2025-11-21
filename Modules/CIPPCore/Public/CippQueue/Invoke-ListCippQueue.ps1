function Invoke-ListCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    param($Request = $null, $TriggerMetadata = $null, $Reference = $null, $QueueId = $null)

    if ($Request) {
        $APIName = $Request.Params.CIPPEndpoint
        Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    }

    $QueueId = $Request.Query.QueueId ?? $QueueId
    $Reference = $Request.Query.Reference ?? $Reference

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    $3HoursAgo = (Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ')

    if ($QueueId) {
        $Filter = "PartitionKey eq 'CippQueue' and RowKey eq '$QueueId'"
    } elseif ($Reference) {
        $Filter = "PartitionKey eq 'CippQueue' and Reference eq '$Reference' and Timestamp ge datetime'$3HoursAgo'"
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

    if ($request) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($QueueData)
            })
    } else {
        return $QueueData
    }
}
