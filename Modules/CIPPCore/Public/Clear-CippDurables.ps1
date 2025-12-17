function Clear-CippDurables {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    # Collect info
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

    $Queues = Get-CIPPAzStorageQueue -Name ('{0}*' -f $FunctionName)

    $RunningQueues = $Queues | Where-Object { $_.ApproximateMessageCount -gt 0 }
    foreach ($Queue in $RunningQueues) {
        Write-Information "- Removing queue: $($Queue.Name), message count: $($Queue.ApproximateMessageCount)"
        if ($PSCmdlet.ShouldProcess($Queue.Name, 'Clear Queue')) {
            $null = Clear-CIPPAzStorageQueue -Name $Queue.Name
        }
    }

    $BlobContainer = '{0}-largemessages' -f $FunctionName
    $containerMatch = Get-CIPPAzStorageContainer -Name $BlobContainer | Where-Object { $_.Name -eq $BlobContainer }
    if ($containerMatch) {
        Write-Information "- Removing blob container: $BlobContainer"
        if ($PSCmdlet.ShouldProcess($BlobContainer, 'Remove Blob Container')) {
            $null = Remove-CIPPAzStorageContainer -Name $BlobContainer
        }
    }

    $null = Get-CippTable -TableName ('{0}History' -f $FunctionName)
    Write-Information 'Durable Orchestrators and Queues have been cleared'
    return $true
}
