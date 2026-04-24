function Push-ScheduledTaskPostExecution {
    <#
    .SYNOPSIS
    Post-execution aggregation function for multi-tenant scheduled tasks

    .DESCRIPTION
    Called by orchestrator after all tenant-specific scheduled task executions complete.
    Aggregates results, updates parent task state, and handles recurrence scheduling.

    .FUNCTIONALITY
    Entrypoint
    #>
    param($Item)

    # Extract parameters and results from the item
    $Parameters = $Item.Parameters
    $Results = $Item.Results

    Write-Information "Post-execution started for scheduled task: $($Parameters.TaskRowKey)"
    Write-Information "Received $($Results.Count) tenant execution results"

    $Table = Get-CippTable -tablename 'ScheduledTasks'

    # Get the parent task
    $ParentTask = Get-AzDataTableEntity @Table -Filter "RowKey eq '$($Parameters.TaskRowKey)'"
    if (!$ParentTask) {
        Write-Warning "Parent task $($Parameters.TaskRowKey) not found in ScheduledTasks table"
        return
    }

    Write-Information "Parent task found: $($ParentTask.Name) - Current state: $($ParentTask.TaskState)"

    # Aggregate results
    $SuccessCount = 0
    $FailureCount = 0
    $TotalTenants = $Results.Count

    foreach ($Result in $Results) {
        if ($Result -and $Result -notlike '*Failed*' -and $Result -notlike '*Error*') {
            $SuccessCount++
        } else {
            $FailureCount++
        }
    }

    Write-Information "Aggregated results: $SuccessCount successful, $FailureCount failed out of $TotalTenants tenants"

    # Determine if this was a recurring task
    $IsRecurring = $ParentTask.Recurrence -and $ParentTask.Recurrence -ne '0'

    # Check trigger execution mode
    $IsTriggerOnce = $false
    if ($ParentTask.Trigger) {
        $Trigger = if (Test-Json -Json $ParentTask.Trigger) {
            $ParentTask.Trigger | ConvertFrom-Json
        } else {
            $ParentTask.Trigger
        }
        $TriggerExecutionMode = $Trigger.ExecutionMode.value ?? $Trigger.ExecutionMode
        if ($TriggerExecutionMode -eq 'once') {
            $IsTriggerOnce = $true
        }
    }

    # Prepare aggregated results message
    $AggregatedMessage = "Multi-tenant task completed: $SuccessCount successful, $FailureCount failed (Total: $TotalTenants tenants)"

    # Calculate next run time for recurring tasks
    if ($IsRecurring -and !$IsTriggerOnce) {
        # Convert recurrence to seconds
        if ($ParentTask.Recurrence -match '^\d+$') {
            $ParentTask.Recurrence = $ParentTask.Recurrence + 'd'
        }

        $secondsToAdd = switch -Regex ($ParentTask.Recurrence) {
            '(\d+)m$' { [int64]$matches[1] * 60 }
            '(\d+)h$' { [int64]$matches[1] * 3600 }
            '(\d+)d$' { [int64]$matches[1] * 86400 }
            default { 0 }
        }

        if ($secondsToAdd -gt 0) {
            $unixtimeNow = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            if ([int64]$ParentTask.ScheduledTime -lt ($unixtimeNow - $secondsToAdd)) {
                $ParentTask.ScheduledTime = $unixtimeNow
            }
            $nextRunUnixTime = [int64]$ParentTask.ScheduledTime + [int64]$secondsToAdd

            Write-Information "Recurring task: next run scheduled for $nextRunUnixTime"

            # Update parent task to 'Planned' state for next execution
            $UpdateEntity = @{
                PartitionKey  = $ParentTask.PartitionKey
                RowKey        = $ParentTask.RowKey
                Results       = $AggregatedMessage
                TaskState     = if ($FailureCount -gt 0 -and $FailureCount -eq $TotalTenants) { 'Failed - Planned' } else { 'Planned' }
                ScheduledTime = "$nextRunUnixTime"
            }
        } else {
            # Invalid recurrence, mark as completed
            Write-Warning "Invalid recurrence value: $($ParentTask.Recurrence). Marking task as completed."
            $UpdateEntity = @{
                PartitionKey = $ParentTask.PartitionKey
                RowKey       = $ParentTask.RowKey
                Results      = "$AggregatedMessage - Warning: Invalid recurrence, task will not repeat"
                TaskState    = 'Completed'
            }
        }
    } else {
        # One-time task or trigger with 'once' mode - mark as completed
        Write-Information 'Non-recurring task: marking as completed'
        $UpdateEntity = @{
            PartitionKey = $ParentTask.PartitionKey
            RowKey       = $ParentTask.RowKey
            Results      = $AggregatedMessage
            TaskState    = if ($FailureCount -gt 0 -and $FailureCount -eq $TotalTenants) { 'Failed' } else { 'Completed' }
        }
    }

    # Update the parent task
    try {
        $null = Update-AzDataTableEntity -Force @Table -Entity $UpdateEntity
        Write-Information "Parent task updated successfully to state: $($UpdateEntity.TaskState)"
    } catch {
        Write-Warning "Failed to update parent task: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }

    # Send consolidated alert/notification if results exist
    # Individual tenant alerts are already sent by Push-ExecScheduledCommand
    # This is just for overall task completion notification if needed
    try {
        if ($Parameters.SendCompletionAlert) {
            Write-Information 'Completion notification available for multi-tenant task'
            Write-Information "Task: $($ParentTask.Name)"
            Write-Information "Results: $SuccessCount successful, $FailureCount failed out of $TotalTenants tenants"
            if ($IsRecurring -and $nextRunUnixTime) {
                $nextRunDate = (Get-Date '1970-01-01').AddSeconds($nextRunUnixTime).ToUniversalTime()
                Write-Information "Next run scheduled for: $($nextRunDate.ToString('yyyy-MM-dd HH:mm:ss UTC'))"
            }
            # Note: Individual tenant results are already in ScheduledTaskResults table
        }
    } catch {
        Write-Warning "Failed to log completion info: $($_.Exception.Message)"
    }

    Write-Information "Post-execution completed for task: $($ParentTask.Name)"
    return @{
        Status            = 'Success'
        TaskState         = $UpdateEntity.TaskState
        SuccessCount      = $SuccessCount
        FailureCount      = $FailureCount
        TotalTenants      = $TotalTenants
        AggregatedMessage = $AggregatedMessage
    }
}
