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

    try { [CIPP.TestDataCache]::ClearExpired() } catch { Write-Information "TestDataCache clearexpired skipped: $($_.Exception.Message)" }

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
        $1HourAgo = (Get-Date).AddHours(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        # Pending = orchestrator claimed but executor not yet started, Running = actively executing
        # Pick up: Planned, Failed-Planned, stuck Pending (>1hr - orphaned claim), or stuck Running/Processing (>4hr for large AllTenants tasks)
        $Filter = "PartitionKey eq 'ScheduledTask' and (TaskState eq 'Planned' or TaskState eq 'Failed - Planned' or (TaskState eq 'Pending' and Timestamp lt datetime'$1HourAgo') or (TaskState eq 'Running' and Timestamp lt datetime'$4HoursAgo') or (TaskState eq 'Processing' and Timestamp lt datetime'$4HoursAgo'))"
        # Disabled is filtered client side: an OData comparison excludes rows that lack the property, which is every task created before the flag existed
        $tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Disabled -ne $true }
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

                if ($task.Command -in (Get-CIPPSchedulerBlockedCommands)) {
                    Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Blocked execution of restricted command '$($task.Command)' in task $($task.Name)" -Sev 'Warning'
                    $null = Update-AzDataTableEntity -Force @Table -Entity @{
                        PartitionKey = $task.PartitionKey
                        RowKey       = $task.RowKey
                        Results      = "Task blocked: '$($task.Command)' is not permitted to run as a scheduled task."
                        TaskState    = 'Failed'
                    }
                    continue
                }

                # Cache Get-Command result to avoid repeated expensive reflection calls
                $CommandInfo = Get-Command -Name $task.Command -ErrorAction SilentlyContinue
                if (-not $CommandInfo) {
                    # Resolve the required module from standardised command name patterns
                    $ModuleToImport = switch -Wildcard ($task.Command) {
                        'Invoke-CIPPStandard*' { 'CIPPStandards' }
                        'Get-CIPPAlert*' { 'CIPPAlerts' }
                        default { $null }
                    }

                    if ($ModuleToImport) {
                        Write-Information "Command '$($task.Command)' not found. Attempting import of '$ModuleToImport' module."
                        $ImportedModule = $false
                        try {
                            if (-not (Get-Module -Name $ModuleToImport)) {
                                Import-Module $ModuleToImport -ErrorAction Stop
                                $ImportedModule = $true
                                Write-Information "Imported module '$ModuleToImport' for command resolution retry."
                            }
                            $CommandInfo = Get-Command -Name $task.Command -ErrorAction Stop
                        } catch {
                            throw "Unable to resolve command '$($task.Command)' for scheduled task '$($task.Name)' after importing '$ModuleToImport'. $($_.Exception.Message)"
                        } finally {
                            if ($ImportedModule) {
                                Remove-Module $ModuleToImport -ErrorAction SilentlyContinue
                            }
                        }
                    } else {
                        throw "Command '$($task.Command)' not found and no module could be resolved from the command name for scheduled task '$($task.Name)'."
                    }
                }
                # The task's authorized tenant is injected into the most specific tenant-identifying
                # parameter the command declares - stored parameter values must never select the tenant.
                $TenantParamNames = [array](@('TenantFilter', 'Tenant', 'TenantId') | Where-Object { $CommandInfo.Parameters.ContainsKey($_) })
                $HasTenantFilter = $TenantParamNames.Count -gt 0
                $PrimaryTenantParam = $TenantParamNames.Count -gt 0 ? $TenantParamNames[0] : $null

                $ScheduledCommand = [pscustomobject]@{
                    Command      = $task.Command
                    Parameters   = $task.Parameters
                    TaskInfo     = $task
                    FunctionName = 'ExecScheduledCommand'
                }

                # Scope is resolved on every run so group membership stays current, as
                # Test-CIPPAuditLogRules does for audit alerts. The stored selection is only trusted
                # on a row the execution gates also read as multi-tenant, otherwise the fan-out here
                # and Push-ExecScheduledCommand would disagree about the task's shape.
                $UsesStoredSelection = $task.Tenants -and $task.Tenant -eq 'AllTenants'
                if ($task.Tenants -and -not $UsesStoredSelection) {
                    Write-Information "Task $($task.Name): ignoring the stored selection, Tenant is '$($task.Tenant)' rather than AllTenants"
                }
                $Selection = if ($UsesStoredSelection) {
                    @($task.Tenants | ConvertFrom-Json -ErrorAction SilentlyContinue)
                } elseif ($task.TenantGroup) {
                    @($task.TenantGroup | ConvertFrom-Json -ErrorAction SilentlyContinue)
                }

                $TargetTenants = $null
                $ResolvedScope = $false
                if ($Selection) {
                    try {
                        $Expanded = Expand-CIPPTenantGroups -TenantFilter $Selection
                    } catch {
                        # Must not fall through to the single-tenant path below: Tenant is the
                        # AllTenants sentinel for a multi-entry selection. Fail the task instead.
                        throw "Failed to expand tenant selection for task $($task.Name): $($_.Exception.Message)"
                    }
                    # Non-group entries pass through unexpanded, so the sentinel survives.
                    $TargetTenants = if ($Expanded.value -contains 'AllTenants') {
                        $TenantList
                    } else {
                        @($TenantList | Where-Object { $_.defaultDomainName -in $Expanded.value })
                    }
                    $ResolvedScope = $true
                } elseif ($task.Tenant -eq 'AllTenants') {
                    # An explicit *All Tenants pick, with no selection stored alongside it
                    $TargetTenants = $TenantList
                    $ResolvedScope = $true
                }

                # Rows predating runtime expansion merged a snapshot of every unselected tenant into
                # excludedTenants, indistinguishable from the operator's own picks, so it is ignored
                # for those. A selection carrying the AllTenants sentinel never had a snapshot
                # written, so its exclusions are the operator's and are kept. excludedTenantGroups
                # was never part of the snapshot either and always applies.
                $IsLegacySnapshot = $UsesStoredSelection -and -not $task.TenantSelectionVersion -and ($Selection.value -notcontains 'AllTenants')
                $ExcludedTenants = [System.Collections.Generic.List[string]]::new()
                if ($task.excludedTenants) {
                    $StoredExclusions = @($task.excludedTenants -split ',' | Where-Object { $_ })
                    if ($IsLegacySnapshot) {
                        # Only report a snapshot that would actually have dropped a tenant in scope
                        # now, or every run of every legacy row logs the same no-op indefinitely.
                        $Reinstated = @($StoredExclusions | Where-Object { $_ -in $TargetTenants.defaultDomainName })
                        if ($Reinstated.Count -gt 0) {
                            Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Task $($task.Name): ignored $($Reinstated.Count) stale snapshot exclusions, tenant group membership is now resolved at runtime" -Sev 'Info'
                        }
                    } else {
                        $ExcludedTenants.AddRange([string[]]$StoredExclusions)
                    }
                }
                if ($task.excludedTenantGroups) {
                    $ExcludedGroups = $task.excludedTenantGroups | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($ExcludedGroups) {
                        $ExcludedTenants.AddRange([string[]]@((Expand-CIPPTenantGroups -TenantFilter $ExcludedGroups).value | Where-Object { $_ }))
                    }
                }

                if ($ResolvedScope) {
                    Write-Information "Task $($task.Name): $(@($TargetTenants).Count) tenants in scope, $($ExcludedTenants.Count) excluded"
                    $FanOutCommands = foreach ($Tenant in $TargetTenants | Where-Object { $_.defaultDomainName -notin $ExcludedTenants }) {
                        $NewParams = $task.Parameters.Clone()
                        if ($HasTenantFilter) {
                            # TenantFilter always carries the execution tenant context; it is stripped
                            # before splatting if the command does not declare it
                            $NewParams.TenantFilter = $Tenant.defaultDomainName
                            $NewParams.$PrimaryTenantParam = $Tenant.defaultDomainName
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
                    if (@($FanOutCommands).Count -gt 0) {
                        $Batch.AddRange(@($FanOutCommands))
                    } else {
                        # Every selected group resolved empty, or was deleted. Close the run out here:
                        # the row is already Pending, and with no batch item no orchestrator or post
                        # execution runs, so it would be reclaimed as stale every hour and a recurring
                        # task would never advance its schedule.
                        $NextRun = Get-CIPPScheduledTaskNextRun -Recurrence $task.Recurrence -ScheduledTime $task.ScheduledTime
                        $EmptyScopeEntity = @{
                            PartitionKey = $task.PartitionKey
                            RowKey       = $task.RowKey
                            Results      = 'No tenants in scope for this task.'
                            ExecutedTime = "$currentUnixTime"
                            TaskState    = $NextRun -gt 0 ? 'Planned' : 'Completed'
                        }
                        if ($NextRun -gt 0) { $EmptyScopeEntity.ScheduledTime = "$NextRun" }
                        $null = Update-AzDataTableEntity -Force @Table -Entity $EmptyScopeEntity
                        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Task $($task.Name): no tenants in scope, nothing to run" -Sev 'Info'
                    }
                } else {
                    # Single tenant
                    if ($HasTenantFilter) {
                        $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                        $ScheduledCommand.Parameters[$PrimaryTenantParam] = $task.Tenant
                    }
                    $Batch.Add($ScheduledCommand)
                }
            } catch {
                $errorMessage = $_.Exception.Message

                # Failed is terminal - the pickup filter only reads Planned and Failed - Planned - so
                # a recurring task parked there never runs again. A transient failure here (a tenant
                # or group table read, say) must not permanently stop it.
                $NextRun = Get-CIPPScheduledTaskNextRun -Recurrence $task.Recurrence -ScheduledTime $task.ScheduledTime
                $FailureEntity = @{
                    PartitionKey = $task.PartitionKey
                    RowKey       = $task.RowKey
                    Results      = "$errorMessage"
                    ExecutedTime = "$currentUnixTime"
                    TaskState    = $NextRun -gt 0 ? 'Failed - Planned' : 'Failed'
                }
                if ($NextRun -gt 0) { $FailureEntity.ScheduledTime = "$NextRun" }
                $null = Update-AzDataTableEntity -Force @Table -Entity $FailureEntity
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
                    # User band: scheduled/run-now tasks must not queue behind P4 background fan-outs.
                    # Explicit because the starter jobs that invoke this function expose no ambient
                    # priority to inherit. Child orchestrations (e.g. OffboardingUser_*) inherit this.
                    Priority         = 2
                }

                if ($PSCmdlet.ShouldProcess('Start-UserTasksOrchestrator', 'Starting Single-Tenant Tasks Orchestrator')) {
                    try {
                        $OrchestratorId = Start-CIPPOrchestrator -InputObject $InputObject
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
                    # User band - see the single-tenant orchestrator above.
                    Priority         = 2
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
                        $OrchestratorId = Start-CIPPOrchestrator -InputObject $InputObject
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
