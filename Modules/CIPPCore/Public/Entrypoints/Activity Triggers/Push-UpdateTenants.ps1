function Push-UpdateTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    Param($Item)
    $QueueReference = 'UpdateTenants'
    $RunningQueue = Invoke-ListCippQueue | Where-Object { $_.Reference -eq $QueueReference -and $_.Status -ne 'Completed' -and $_.Status -ne 'Failed' }
    if ($RunningQueue) {
        Write-Host 'Update Tenants already running'
        return
    }
    $Queue = New-CippQueueEntry -Name 'Update Tenants' -Reference $QueueReference -TotalTasks 1
    try {
        $QueueTask = @{
            QueueId = $Queue.RowKey
            Name    = 'Get tenant list'
            Status  = 'Running'
        }
        $TaskStatus = Set-CippQueueTask @QueueTask
        $QueueTask.TaskId = $TaskStatus.RowKey
        Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Running'
        Get-Tenants -IncludeAll -TriggerRefresh | Out-Null
        Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Completed'
        $QueueTask.Status = 'Completed'
        Set-CippQueueTask @QueueTask
    } catch {
        Write-Host "Queue Error: $($_.Exception.Message)"
        Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Failed'
        $QueueTask.Status = 'Failed'
        Set-CippQueueTask @QueueTask
    }
}