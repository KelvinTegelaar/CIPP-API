function Invoke-ListCippQueue {
    # Input bindings are passed in via param block.
    param($Request = $null, $TriggerMetadata = $null)

    if ($Request) {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'
    }

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    $CippQueueData = Get-CIPPAzDataTableEntity @CippQueue | Where-Object { ($_.Timestamp.DateTime) -ge (Get-Date).ToUniversalTime().AddHours(-1) } | Sort-Object -Property Timestamp -Descending

    $QueueData = foreach ($Queue in $CippQueueData) {
        $Tasks = Get-CIPPAzDataTableEntity @CippQueueTasks -Filter "QueueId eq '$($Queue.RowKey)'" -Property Timestamp, Name, Status | Sort-Object -Property Name -Unique
        $TaskStatus = @{}
        $Tasks | Group-Object -Property Status | ForEach-Object {
            $TaskStatus.$($_.Name) = $_.Count
        }

        if ($Tasks) {
            if ($Tasks.Status -notcontains 'Running') {
                if ($Tasks.Status -notcontains 'Failed') {
                    $Queue.Status = 'Completed'
                } else {
                    $Queue.Status = 'Completed (with errors)'
                }
            } else {
                $Queue.Status = 'Running'
            }
        }

        [PSCustomObject]@{
            PartitionKey    = $Queue.PartitionKey
            RowKey          = $Queue.RowKey
            Name            = $Queue.Name
            Link            = $Queue.Link
            Reference       = $Queue.Reference
            TotalTasks      = $Queue.TotalTasks
            CompletedTasks  = $TaskStatus.Completed ?? 0
            RunningTasks    = $TaskStatus.Running ?? 0
            FailedTasks     = $TaskStatus.Failed ?? 0
            PercentComplete = [math]::Round((($TaskStatus.Completed / $Queue.TotalTasks) * 100), 1)
            PercentFailed   = [math]::Round((($TaskStatus.Failed / $Queue.TotalTasks) * 100), 1)
            PercentRunning  = [math]::Round((($TaskStatus.Running / $Queue.TotalTasks) * 100), 1)
            Tasks           = $Tasks
            Status          = $Queue.Status
            Timestamp       = $Queue.Timestamp
        }

    }

    if ($request) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($QueueData)
            })
    } else {
        return $QueueData
    }
}