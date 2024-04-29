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
    $Queue = New-CippQueueEntry -Name 'Update Tenants' -Reference $QueueReference
    try {
        Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Running'
        Get-Tenants | Out-Null
        Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Completed'
    } catch {
        Write-Host "Queue Error: $($_.Exception.Message)"
        Update-CippQueueEntry -RowKey $Queue.RowKey -Status 'Failed'
    }
}