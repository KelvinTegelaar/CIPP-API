function Invoke-ListCippQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    param($Request = $null, $TriggerMetadata = $null)

    if ($Request) {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'
    }

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    $CippQueueData = Get-CIPPAzDataTableEntity @CippQueue | Where-Object { ($_.Timestamp.DateTime) -ge (Get-Date).ToUniversalTime().AddHours(-3) } | Sort-Object -Property Timestamp -Descending

    $QueueData = foreach ($Queue in $CippQueueData) {
        $Tasks = Get-CIPPAzDataTableEntity @CippQueueTasks -Filter "QueueId eq '$($Queue.RowKey)'" | Where-Object { $_.Name } | Select-Object Timestamp, Name, Status
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
            Tasks           = @($Tasks)
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