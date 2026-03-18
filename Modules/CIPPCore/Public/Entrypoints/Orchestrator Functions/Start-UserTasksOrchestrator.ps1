function Start-UserTasksOrchestrator {
    <#
    .SYNOPSIS
    Start the User Tasks Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TaskId = $null
    )

    $Table = Get-CippTable -tablename 'ScheduledTasks'

    if ($TaskId) {
        $Filter = "PartitionKey eq 'ScheduledTask' and RowKey eq '$TaskId'"
        $task = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        if (-not $task.RowKey) {
            Write-Warning "No scheduled task found with ID: $TaskId"
            return
        } else {
            Write-Information "Starting orchestrator for scheduled task: $($task.Name) with ID: $TaskId"
            $tasks = @($task)
        }
    } else {
        $4HoursAgo = (Get-Date).AddHours(-4).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $24HoursAgo = (Get-Date).AddHours(-24).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        # Pending = orchestrator queued, Running = actively executing
        # Pick up: Planned, Failed-Planned, stuck Pending (>24hr), or stuck Running (>4hr for large AllTenants tasks)
        $Filter = "PartitionKey eq 'ScheduledTask' and (TaskState eq 'Planned' or TaskState eq 'Failed - Planned' or (TaskState eq 'Pending' and Timestamp lt datetime'$24HoursAgo') or (TaskState eq 'Running' and Timestamp lt datetime'$4HoursAgo') or (TaskState eq 'Processing' and Timestamp lt datetime'$4HoursAgo'))"
        $tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    }

    $Batch = [System.Collections.Generic.List[object]]::new()
    $TenantList = Get-Tenants -IncludeErrors
    foreach ($task in $tasks) {
        $tenant = $task.Tenant

        $currentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        if ($currentUnixTime -ge $task.ScheduledTime) {
            try {
                # Update task state to 'Pending' immediately to prevent concurrent orchestrator runs from picking it up
                # 'Pending' = orchestrator has picked it up and is queuing commands
                # 'Running' = actual execution is happening (set by Push-ExecScheduledCommand)
                # Use ETag for optimistic concurrency to prevent race conditions
                try {
                    $null = Update-AzDataTableEntity @Table -Entity @{
                        PartitionKey = $task.PartitionKey
                        RowKey       = $task.RowKey
                        ExecutedTime = "$currentUnixTime"
                        TaskState    = 'Pending'
                        ETag         = $task.ETag
                    }
                } catch {
                    # Task was already picked up by another orchestrator instance - skip it
                    Write-Information "Task $($task.Name) already being processed by another orchestrator instance. Skipping."
                    continue
                }
                $task.Parameters = $task.Parameters | ConvertFrom-Json -AsHashtable
                if (!$task.Parameters) { $task.Parameters = @{} }

                # Cache Get-Command result to avoid repeated expensive reflection calls
                $CommandInfo = Get-Command $task.Command
                $HasTenantFilter = $CommandInfo.Parameters.ContainsKey('TenantFilter')

                $ScheduledCommand = [pscustomobject]@{
                    Command      = $task.Command
                    Parameters   = $task.Parameters
                    TaskInfo     = $task
                    FunctionName = 'ExecScheduledCommand'
                }

                if ($task.Tenant -eq 'AllTenants') {
                    $ExcludedTenants = $task.excludedTenants -split ','
                    Write-Host "Excluded Tenants from this task: $ExcludedTenants"
                    $AllTenantCommands = foreach ($Tenant in $TenantList | Where-Object { $_.defaultDomainName -notin $ExcludedTenants }) {
                        $NewParams = $task.Parameters.Clone()
                        if ($HasTenantFilter) {
                            $NewParams.TenantFilter = $Tenant.defaultDomainName
                        }
                        # Clone TaskInfo to prevent shared object references
                        $TaskInfoClone = $task.PSObject.Copy()
                        [pscustomobject]@{
                            Command      = $task.Command
                            Parameters   = $NewParams
                            TaskInfo     = $TaskInfoClone
                            FunctionName = 'ExecScheduledCommand'
                        }
                    }
                    $Batch.AddRange($AllTenantCommands)
                } elseif ($task.TenantGroup) {
                    # Handle tenant groups - expand group to individual tenants
                    try {
                        $TenantGroupObject = $task.TenantGroup | ConvertFrom-Json
                        Write-Host "Expanding tenant group: $($TenantGroupObject.label) with ID: $($TenantGroupObject.value)"

                        # Create a tenant filter object for expansion
                        $TenantFilterForExpansion = @([PSCustomObject]@{
                                type  = 'Group'
                                value = $TenantGroupObject.value
                                label = $TenantGroupObject.label
                            })

                        # Expand the tenant group to individual tenants
                        $ExpandedTenants = Expand-CIPPTenantGroups -TenantFilter $TenantFilterForExpansion

                        $ExcludedTenants = $task.excludedTenants -split ','
                        Write-Host "Excluded Tenants from this task: $ExcludedTenants"

                        $GroupTenantCommands = foreach ($ExpandedTenant in $ExpandedTenants | Where-Object { $_.value -notin $ExcludedTenants }) {
                            $NewParams = $task.Parameters.Clone()
                            if ($HasTenantFilter) {
                                $NewParams.TenantFilter = $ExpandedTenant.value
                            }
                            # Clone TaskInfo to prevent shared object references
                            $TaskInfoClone = $task.PSObject.Copy()
                            [pscustomobject]@{
                                Command      = $task.Command
                                Parameters   = $NewParams
                                TaskInfo     = $TaskInfoClone
                                FunctionName = 'ExecScheduledCommand'
                            }
                        }
                        $Batch.AddRange($GroupTenantCommands)
                    } catch {
                        Write-Host "Error expanding tenant group: $($_.Exception.Message)"
                        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Failed to expand tenant group for task $($task.Name): $($_.Exception.Message)" -sev Error

                        # Fall back to treating as single tenant
                        if ($HasTenantFilter) {
                            $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                        }
                        $Batch.Add($ScheduledCommand)
                    }
                } else {
                    # Handle single tenant
                    if ($HasTenantFilter) {
                        $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                    }
                    $Batch.Add($ScheduledCommand)
                }
            } catch {
                $errorMessage = $_.Exception.Message

                $null = Update-AzDataTableEntity -Force @Table -Entity @{
                    PartitionKey = $task.PartitionKey
                    RowKey       = $task.RowKey
                    Results      = "$errorMessage"
                    ExecutedTime = "$currentUnixTime"
                    TaskState    = 'Failed'
                }
                Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Failed to execute task $($task.Name): $errorMessage" -sev Error
            }
        }
    }

    Write-Information 'Batching tasks for execution...'
    Write-Information "Total tasks to process: $($Batch.Count)"

    if ($Batch.Count -gt 0) {
        # Separate multi-tenant tasks from single-tenant tasks
        $MultiTenantTasks = [System.Collections.Generic.List[object]]::new()
        $SingleTenantTasks = [System.Collections.Generic.List[object]]::new()

        foreach ($Task in $Batch) {
            $IsMultiTenant = ($Task.TaskInfo.Tenant -eq 'AllTenants' -or $Task.TaskInfo.TenantGroup)
            if ($IsMultiTenant) {
                $MultiTenantTasks.Add($Task)
            } else {
                $SingleTenantTasks.Add($Task)
            }
        }

        Write-Information "Multi-tenant tasks: $($MultiTenantTasks.Count), Single-tenant tasks: $($SingleTenantTasks.Count)"

        # Process single-tenant tasks: Group by tenant for efficiency
        if ($SingleTenantTasks.Count -gt 0) {
            $TenantGroups = $SingleTenantTasks | Group-Object -Property { $_.Parameters.TenantFilter }

            foreach ($TenantGroup in $TenantGroups) {
                $TenantName = $TenantGroup.Name
                $TenantCommands = @($TenantGroup.Group)

                Write-Information "Creating orchestrator for single-tenant tasks: $TenantName with $($TenantCommands.Count) tasks"

                # Create queue entry for this tenant's tasks
                $Queue = New-CippQueueEntry -Name "Scheduled Tasks - $TenantName"
                $QueueId = $Queue.RowKey
                $BatchWithQueue = @($TenantCommands | Select-Object *, @{Name = 'QueueId'; Expression = { $QueueId } }, @{Name = 'QueueName'; Expression = { '{0} - {1}' -f $_.TaskInfo.Name, $TenantName } })

                $InputObject = [PSCustomObject]@{
                    OrchestratorName = "UserTaskOrchestrator_$TenantName"
                    Batch            = $BatchWithQueue
                    SkipLog          = $true
                }

                if ($PSCmdlet.ShouldProcess('Start-UserTasksOrchestrator', 'Starting Single-Tenant Tasks Orchestrator')) {
                    try {
                        $OrchestratorId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
                        Write-Information "Single-tenant orchestrator started for $TenantName with ID: $OrchestratorId"
                    } catch {
                        Write-Warning "Failed to start single-tenant orchestrator for $TenantName : $($_.Exception.Message)"
                        Write-Information $_.InvocationInfo.PositionMessage
                    }
                }
            }
        }

        # Process multi-tenant tasks: Each gets its own orchestrator with PostExecution
        if ($MultiTenantTasks.Count -gt 0) {
            # Group by parent task (RowKey) to handle each multi-tenant task separately
            $ParentTaskGroups = $MultiTenantTasks | Group-Object -Property { $_.TaskInfo.RowKey }

            foreach ($ParentTaskGroup in $ParentTaskGroups) {
                $ParentTask = $ParentTaskGroup.Group[0].TaskInfo
                $TaskCommands = @($ParentTaskGroup.Group)

                Write-Information "Creating orchestrator for multi-tenant task: $($ParentTask.Name) with $($TaskCommands.Count) tenant executions"

                # Combine all tenant executions for this parent task
                $AllBatchItems = [System.Collections.Generic.List[object]]::new()

                # Group by tenant within this parent task for queue organization
                $TenantSubGroups = $TaskCommands | Group-Object -Property { $_.Parameters.TenantFilter }

                foreach ($TenantSubGroup in $TenantSubGroups) {
                    $TenantName = $TenantSubGroup.Name
                    $TenantItems = @($TenantSubGroup.Group)

                    Write-Information "  Including tenant: $TenantName with $($TenantItems.Count) items"

                    # Create queue entry for each tenant within this multi-tenant task
                    $Queue = New-CippQueueEntry -Name "Scheduled Tasks - $TenantName"
                    $QueueId = $Queue.RowKey
                    $BatchWithQueue = @($TenantItems | Select-Object *, @{Name = 'QueueId'; Expression = { $QueueId } }, @{Name = 'QueueName'; Expression = { '{0} - {1}' -f $ParentTask.Name, $TenantName } })

                    $AllBatchItems.AddRange($BatchWithQueue)
                }

                $InputObject = [PSCustomObject]@{
                    OrchestratorName = "UserTaskOrchestrator_$($ParentTask.Name)"
                    Batch            = @($AllBatchItems)
                    SkipLog          = $true
                    PostExecution    = @{
                        FunctionName = 'ScheduledTaskPostExecution'
                        Parameters   = @{
                            TaskRowKey          = $ParentTask.RowKey
                            TaskName            = $ParentTask.Name
                            SendCompletionAlert = $true
                        }
                    }
                }

                Write-Information "Starting multi-tenant orchestrator for task: $($ParentTask.Name) with $($AllBatchItems.Count) total executions"

                if ($PSCmdlet.ShouldProcess('Start-UserTasksOrchestrator', 'Starting Multi-Tenant Task Orchestrator')) {
                    try {
                        $OrchestratorId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
                        Write-Information "Multi-tenant orchestrator started for $($ParentTask.Name) with ID: $OrchestratorId"
                    } catch {
                        Write-Warning "Failed to start multi-tenant orchestrator for $($ParentTask.Name): $($_.Exception.Message)"
                        Write-Information $_.InvocationInfo.PositionMessage
                    }
                }
            }
        }
    }
}
