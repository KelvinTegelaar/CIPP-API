function Clear-CippDurables {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    # Collect info
    $StorageContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
    $FunctionName = $env:WEBSITE_SITE_NAME -replace '-', ''

    # Get orchestrators
    $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f $FunctionName)
    $HistoryTable = Get-CippTable -TableName ('{0}History' -f $FunctionName)
    $QueueTable = Get-CippTable -TableName 'CippQueue'
    $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'

    Remove-AzDataTable @InstancesTable
    Remove-AzDataTable @HistoryTable
    Remove-AzDataTable @QueueTable
    Remove-AzDataTable @CippQueueTasks

    $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount, QueueClient

    $RunningQueues = $Queues | Where-Object { $_.ApproximateMessageCount -gt 0 }
    foreach ($Queue in $RunningQueues) {
        Write-Information "- Removing queue: $($Queue.Name), message count: $($Queue.ApproximateMessageCount)"
        if ($PSCmdlet.ShouldProcess($Queue.Name, 'Clear Queue')) {
            $Queue.QueueClient.ClearMessagesAsync()
        }
    }

    $BlobContainer = '{0}-largemessages' -f $FunctionName
    if (Get-AzStorageContainer -Name $BlobContainer -Context $StorageContext -ErrorAction SilentlyContinue) {
        Write-Information "- Removing blob container: $BlobContainer"
        if ($PSCmdlet.ShouldProcess($BlobContainer, 'Remove Blob Container')) {
            Remove-AzStorageContainer -Name $BlobContainer -Context $StorageContext -Confirm:$false -Force
        }
    }

    $null = Get-CippTable -TableName ('{0}History' -f $FunctionName)
    Write-Information 'Durable Orchestrators and Queues have been cleared'
    return $true
}
