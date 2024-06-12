function Clear-CippDurables {
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param()
    # Collect info
    $StorageContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
    $FunctionName = $env:WEBSITE_SITE_NAME

    # Get orchestrators
    $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f $FunctionName)
    $HistoryTable = Get-CippTable -TableName ('{0}History' -f $FunctionName)
    $Yesterday = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "CreatedTime ge datetime'$Yesterday' or RuntimeStatus eq 'Pending' or RuntimeStatus eq 'Running'"
    $Instances = Get-CippAzDataTableEntity @InstancesTable -Filter $Filter

    $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount, QueueClient

    $RunningQueues = $Queues | Where-Object { $_.ApproximateMessageCount -gt 0 }
    foreach ($Queue in $RunningQueues) {
        Write-Information "- Removing queue: $($Queue.Name), message count: $($Queue.ApproximateMessageCount)"
        if ($PSCmdlet.ShouldProcess($Queue.Name, 'Clear Queue')) {
            $Queue.QueueClient.ClearMessagesAsync()
        }
    }

    $QueueTable = Get-CippTable -TableName 'CippQueue'
    $CippQueue = Invoke-ListCippQueue
    $QueueEntities = foreach ($Queue in $CippQueue) {
        if ($Queue.Status -eq 'Running') {
            $Queue.TotalTasks = $Queue.CompletedTasks
            $Queue | Select-Object -Property PartitionKey, RowKey, TotalTasks
        }
    }
    if (($QueueEntities | Measure-Object).Count -gt 0) {
        if ($PSCmdlet.ShouldProcess('Queues', 'Mark Failed')) {
            Update-AzDataTableEntity @QueueTable -Entity $QueueEntities
        }
    }

    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
    $RunningTasks = Get-CIPPAzDataTableEntity @CippQueueTasks -Filter "Status eq 'Running'" -Property RowKey, PartitionKey, Status
    if (($RunningTasks | Measure-Object).Count -gt 0) {
        if ($PSCmdlet.ShouldProcess('Tasks', 'Mark Failed')) {
            $UpdatedTasks = foreach ($Task in $RunningTasks) {
                $Task.Status = 'Failed'
                $Task
            }
            Update-AzDataTableEntity @CippQueueTasks -Entity $UpdatedTasks
        }
    }

    Remove-AzDataTable @InstancesTable
    Remove-AzDataTable @HistoryTable
    $BlobContainer = '{0}-largemessages' -f $Function.Name
    if (Get-AzStorageContainer -Name $BlobContainer -Context $StorageContext -ErrorAction SilentlyContinue) {
        Write-Information "- Removing blob container: $BlobContainer"
        if ($PSCmdlet.ShouldProcess($BlobContainer, 'Remove Blob Container')) {
            Remove-AzStorageContainer -Name $BlobContainer -Context $StorageContext -Confirm:$false -Force
        }
    }
    $null = Get-CippTable -TableName ('{0}History' -f $FunctionName)
    Write-Information 'Durable Orchestrators and Queues have been cleared'
}