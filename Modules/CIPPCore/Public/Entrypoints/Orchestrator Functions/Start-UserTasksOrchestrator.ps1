function Start-UserTasksOrchestrator {
    <#
    .SYNOPSIS
    Start the User Tasks Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Table = Get-CippTable -tablename 'ScheduledTasks'
    $30MinutesAgo = (Get-Date).AddMinutes(-30).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $4HoursAgo = (Get-Date).AddHours(-4).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    # Pending = orchestrator queued, Running = actively executing
    # Pick up: Planned, Failed-Planned, stuck Pending (>30min), or stuck Running (>4hr for large AllTenants tasks)
    $Filter = "PartitionKey eq 'ScheduledTask' and (TaskState eq 'Planned' or TaskState eq 'Failed - Planned' or (TaskState eq 'Pending' and Timestamp lt datetime'$30MinutesAgo') or (TaskState eq 'Running' and Timestamp lt datetime'$4HoursAgo'))"
    $tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter

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
                $null = Update-AzDataTableEntity -Force @Table -Entity @{
                    PartitionKey = $task.PartitionKey
                    RowKey       = $task.RowKey
                    ExecutedTime = "$currentUnixTime"
                    TaskState    = 'Pending'
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
        # Group tasks by tenant instead of command type
        $TenantGroups = $Batch | Group-Object -Property { $_.Parameters.TenantFilter }
        $ProcessedBatches = [System.Collections.Generic.List[object]]::new()

        foreach ($TenantGroup in $TenantGroups) {
            $TenantName = $TenantGroup.Name
            $TenantCommands = [System.Collections.Generic.List[object]]::new($TenantGroup.Group)

            Write-Information "Creating batch for tenant: $TenantName with $($TenantCommands.Count) tasks"
            $ProcessedBatches.Add($TenantCommands)
        }

        # Process each tenant batch separately
        foreach ($ProcessedBatch in $ProcessedBatches) {
            $TenantName = $ProcessedBatch[0].Parameters.TenantFilter
            Write-Information "Processing batch for tenant: $TenantName with $($ProcessedBatch.Count) tasks..."
            Write-Information 'Tasks by command:'
            $ProcessedBatch | Group-Object -Property Command | ForEach-Object {
                Write-Information " - $($_.Name): $($_.Count)"
            }

            # Create queue entry for each tenant batch
            $Queue = New-CippQueueEntry -Name "Scheduled Tasks - $TenantName"
            $QueueId = $Queue.RowKey
            $BatchWithQueue = $ProcessedBatch | Select-Object *, @{Name = 'QueueId'; Expression = { $QueueId } }, @{Name = 'QueueName'; Expression = { '{0} - {1}' -f $_.TaskInfo.Name, $TenantName } }

            $InputObject = [PSCustomObject]@{
                OrchestratorName = "UserTaskOrchestrator_$TenantName"
                Batch            = @($BatchWithQueue)
                SkipLog          = $true
            }

            if ($PSCmdlet.ShouldProcess('Start-UserTasksOrchestrator', 'Starting User Tasks Orchestrator')) {
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
            }
        }
    }
}
