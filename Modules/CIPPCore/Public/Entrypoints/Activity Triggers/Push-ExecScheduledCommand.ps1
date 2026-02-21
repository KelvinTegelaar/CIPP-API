function Push-ExecScheduledCommand {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)
    $item = $Item | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    Write-Information "We are going to be running a scheduled task: $($Item.TaskInfo | ConvertTo-Json -Depth 10)"

    # Define orchestrator-based commands that handle their own post-execution and state updates
    $OrchestratorBasedCommands = @('Invoke-CIPPOffboardingJob')

    # Initialize AsyncLocal storage for thread-safe per-invocation context
    if (-not $script:CippScheduledTaskIdStorage) {
        $script:CippScheduledTaskIdStorage = [System.Threading.AsyncLocal[string]]::new()
    }
    $script:CippScheduledTaskIdStorage.Value = $Item.TaskInfo.RowKey

    $Table = Get-CippTable -tablename 'ScheduledTasks'
    $task = $Item.TaskInfo
    $commandParameters = $Item.Parameters | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

    # Handle tenant resolution - support both direct tenant and group-expanded tenants
    $Tenant = $Item.Parameters.TenantFilter ?? $Item.TaskInfo.Tenant

    # Detect if this is a multi-tenant task that should store results per-tenant
    $IsMultiTenantTask = ($task.Tenant -eq 'AllTenants' -or $task.TenantGroup)

    # For tenant group tasks, the tenant will be the expanded tenant from the orchestrator
    # We don't need to expand groups here as that's handled in the orchestrator
    $TenantInfo = Get-Tenants -TenantFilter $Tenant

    $CurrentTask = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$($task.PartitionKey)' and RowKey eq '$($task.RowKey)'"
    if (!$CurrentTask) {
        Write-Information "The task $($task.Name) for tenant $($task.Tenant) does not exist in the ScheduledTasks table. Exiting."
        Remove-Variable -Name ScheduledTaskId -Scope Script -ErrorAction SilentlyContinue
        return
    }
    if ($CurrentTask.TaskState -eq 'Completed' -and !$IsMultiTenantTask) {
        Write-Information "The task $($task.Name) for tenant $($task.Tenant) is already completed. Skipping execution."
        Remove-Variable -Name ScheduledTaskId -Scope Script -ErrorAction SilentlyContinue
        return
    }
    # Task should be 'Pending' (queued by orchestrator) or 'Running' (retry/recovery)
    # We accept both to handle edge cases

    # Check for rerun protection - prevent duplicate executions within the recurrence interval
    if ($task.Recurrence -and $task.Recurrence -ne '0') {
        # Calculate interval in seconds from recurrence string
        $IntervalSeconds = switch -Regex ($task.Recurrence) {
            '^(\d+)$' { [int64]$matches[1] * 86400 }  # Plain number = days
            '(\d+)m$' { [int64]$matches[1] * 60 }
            '(\d+)h$' { [int64]$matches[1] * 3600 }
            '(\d+)d$' { [int64]$matches[1] * 86400 }
            default { 0 }
        }

        if ($IntervalSeconds -gt 0) {
            # Round down to nearest 15-minute interval (900 seconds) since that's when orchestrator runs
            # This prevents rerun blocking issues due to slight timing variations
            $FifteenMinutes = 900
            $AdjustedInterval = [Math]::Floor($IntervalSeconds / $FifteenMinutes) * $FifteenMinutes

            # Ensure we have at least one 15-minute interval
            if ($AdjustedInterval -lt $FifteenMinutes) {
                $AdjustedInterval = $FifteenMinutes
            }
            # Use task RowKey as API identifier for rerun cache
            $RerunParams = @{
                TenantFilter = $Tenant
                Type         = 'ScheduledTask'
                API          = $task.RowKey
                Interval     = $AdjustedInterval
                BaseTime     = [int64]$task.ScheduledTime
                Headers      = $Headers
            }

            $IsRerun = Test-CIPPRerun @RerunParams
            if ($IsRerun) {
                Write-Information "Scheduled task $($task.Name) for tenant $Tenant was recently executed. Skipping to prevent duplicate execution."
                Remove-Variable -Name ScheduledTaskId -Scope Script -ErrorAction SilentlyContinue
                return
            }
        }
    }

    if ($task.Trigger) {
        # Extract trigger data from the task and process
        $Trigger = if (Test-Json -Json $task.Trigger) { $task.Trigger | ConvertFrom-Json } else { $task.Trigger }
        $TriggerType = $Trigger.Type.value ?? $Trigger.Type
        if ($TriggerType -eq 'DeltaQuery') {
            $IsTriggerTask = $true
            $DeltaUrl = Get-DeltaQueryUrl -TenantFilter $Tenant -PartitionKey $task.RowKey
            $DeltaQuery = @{
                DeltaUrl     = $DeltaUrl
                TenantFilter = $Tenant
                PartitionKey = $task.RowKey
            }
            $Query = New-GraphDeltaQuery @DeltaQuery

            $secondsToAdd = switch -Regex ($task.Recurrence) {
                '(\d+)m$' { [int64]$matches[1] * 60 }
                '(\d+)h$' { [int64]$matches[1] * 3600 }
                '(\d+)d$' { [int64]$matches[1] * 86400 }
                default { 0 }
            }

            $Minutes = [int]($secondsToAdd / 60)

            $DeltaQueryConditions = @{
                Query        = $Query
                Trigger      = $Trigger
                TenantFilter = $Tenant
                LastTrigger  = [datetime]::UtcNow.AddMinutes(-$Minutes)
            }
            $DeltaResults = Test-DeltaQueryConditions @DeltaQueryConditions

            if (-not $DeltaResults.ConditionsMet) {
                Write-Information "Delta query conditions not met for tenant $Tenant. Skipping execution."
                # update interval
                $nextRunUnixTime = [int64]$task.ScheduledTime + [int64]$secondsToAdd
                $null = Update-AzDataTableEntity -Force @Table -Entity @{
                    PartitionKey  = $task.PartitionKey
                    RowKey        = $task.RowKey
                    TaskState     = 'Planned'
                    ScheduledTime = [string]$nextRunUnixTime
                }
                Remove-Variable -Name ScheduledTaskId -Scope Script -ErrorAction SilentlyContinue
                return
            }
        }
    } else {
        $IsTriggerTask = $false
    }

    $null = Update-AzDataTableEntity -Force @Table -Entity @{
        PartitionKey = $task.PartitionKey
        RowKey       = $task.RowKey
        TaskState    = 'Running'
    }

    $Function = Get-Command -Name $Item.Command
    if ($null -eq $Function) {
        $Results = "Task Failed: The command $($Item.Command) does not exist."
        $State = 'Failed'
        Update-AzDataTableEntity -Force @Table -Entity @{
            PartitionKey = $task.PartitionKey
            RowKey       = $task.RowKey
            Results      = "$Results"
            TaskState    = $State
        }

        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $Tenant -tenantid $TenantInfo.customerId -message "Failed to execute task $($task.Name): The command $($Item.Command) does not exist." -sev Error
        Remove-Variable -Name ScheduledTaskId -Scope Script -ErrorAction SilentlyContinue
        return
    }

    try {
        $PossibleParams = $Function.Parameters.Keys
        $keysToRemove = [System.Collections.Generic.List[string]]@()
        foreach ($key in $commandParameters.Keys) {
            if (-not ($PossibleParams -contains $key)) {
                $keysToRemove.Add($key)
            }
        }
        foreach ($key in $keysToRemove) {
            $commandParameters.Remove($key)
        }
    } catch {
        Write-Information "Failed to remove parameters: $($_.Exception.Message)"
    }

    if ($IsTriggerTask -eq $true -and $Trigger.ExecutePerResource -ne $true) {
        # iterate through paramters looking for %variables% and replace them with matched data from the delta query
        # examples would be %id% to be the id of the result
        # if %triggerdata% is found, pass the entire matched data object
        try {
            foreach ($key in $commandParameters.Keys) {
                if ($commandParameters[$key] -is [string]) {
                    if ($commandParameters[$key] -match '^%(.*)%$') {
                        $variableName = $matches[1]
                        if ($variableName -eq 'triggerdata') {
                            Write-Information "Replacing parameter $key with full matched data object."
                            $commandParameters[$key] = $DeltaResults.MatchedData
                        } else {
                            # Replace with array of matched property values
                            Write-Information "Replacing parameter $key with matched data property '$variableName'."
                            $commandParameters[$key] = $DeltaResults.MatchedData | Select-Object -ExpandProperty $variableName
                        }
                    }
                }
            }
        } catch {
            Write-Information "Failed to process trigger data parameters: $($_.Exception.Message)"
        }
    } elseif ($IsTriggerTask -eq $true -and $Trigger.ExecutePerResource -eq $true) {
        Write-Information 'This is a trigger task with ExecutePerResource set to true. Iterating through matched data to execute command per resource.'
        $results = foreach ($dataItem in $DeltaResults.MatchedData) {
            $individualCommandParameters = $commandParameters.Clone()
            try {
                foreach ($key in $individualCommandParameters.Keys) {
                    if ($individualCommandParameters[$key] -is [string]) {
                        if ($individualCommandParameters[$key] -match '^%(.*)%$') {
                            if ($matches[1] -eq 'triggerdata') {
                                Write-Information "Replacing parameter $key with full matched data object for individual execution."
                                $individualCommandParameters[$key] = $dataItem
                            } else {
                                $variableName = $matches[1]
                                Write-Information "Replacing parameter $key with matched data property '$variableName' for individual execution."
                                $individualCommandParameters[$key] = $dataItem.$variableName
                            }
                        }
                    }
                }
            } catch {
                Write-Information "Failed to process trigger data parameters for individual execution: $($_.Exception.Message)"
            }
            try {
                Write-Information "Executing command $($Item.Command) for individual matched data item with parameters: $($individualCommandParameters | ConvertTo-Json -Depth 10)"
                & $Item.Command @individualCommandParameters
                Write-Information "Results for individual execution: $($results | ConvertTo-Json -Depth 10)"
            } catch {
                Write-Information "Failed to execute command for individual matched data item: $($_.Exception.Message)"
            }
        }
    }

    try {
        if (-not $Trigger.ExecutePerResource) {
            try {
                # For orchestrator-based commands, add TaskInfo to enable post-execution updates
                if ($Item.Command -eq 'Invoke-CIPPOffboardingJob') {
                    Write-Information 'Adding TaskInfo to command parameters for orchestrator-based offboarding'
                    $commandParameters['TaskInfo'] = $task
                }

                Write-Information "Starting task: $($Item.Command) for tenant: $Tenant with parameters: $($commandParameters | ConvertTo-Json)"
                $results = & $Item.Command @commandParameters
            } catch {
                $results = "Task Failed: $($_.Exception.Message)"
                $State = 'Failed'
            }
            Write-Information 'Ran the command. Processing results'
        }
        Write-Information "Results: $($results | ConvertTo-Json -Depth 10)"
        if ($item.command -like 'Get-CIPPAlert*') {
            Write-Information 'This is an alert task. Processing results as alerts.'
            $results = @($results)
            $TaskType = 'Alert'
        } else {
            Write-Information 'This is a scheduled task. Processing results as scheduled task.'
            $TaskType = 'Scheduled Task'

            if (!$results) {
                $results = 'Task completed successfully'
            }

            if ($results -is [String]) {
                $results = @{ Results = $results }
            } elseif ($results -is [array] -and $results[0] -is [string] -or $results[0].resultText -is [string]) {
                $results = $results | Where-Object { $_ -is [string] -or $_.resultText -is [string] }
                $results = $results | ForEach-Object {
                    $Message = $_.resultText ?? $_
                    @{ Results = $Message }
                }
            }
            Write-Information "Results after processing: $($results | ConvertTo-Json -Depth 10)"
            Write-Information 'Moving onto storing results'
            if ($results -is [string]) {
                $StoredResults = $results
            } else {
                $results = $results | Select-Object * -ExcludeProperty RowKey, PartitionKey
                $StoredResults = $results | ConvertTo-Json -Compress -Depth 20 | Out-String
            }
        }
        Write-Information "Results: $($results | ConvertTo-Json -Depth 10)"
        if ($StoredResults.Length -gt 64000 -or $IsMultiTenantTask) {
            $TaskResultsTable = Get-CippTable -tablename 'ScheduledTaskResults'
            $TaskResults = @{
                PartitionKey = $task.RowKey
                RowKey       = $Tenant
                Results      = [string](ConvertTo-Json -Compress -Depth 20 $results)
            }
            $null = Add-CIPPAzDataTableEntity @TaskResultsTable -Entity $TaskResults -Force
            $StoredResults = @{ Results = 'Completed, details are available in the More Info pane' } | ConvertTo-Json -Compress
        }
    } catch {
        Write-Information "Failed to run task: $($_.Exception.Message)"
        $errorMessage = $_.Exception.Message
        #if recurrence is just a number, add it in days.
        if ($task.Recurrence -match '^\d+$') {
            $task.Recurrence = $task.Recurrence + 'd'
        }
        $secondsToAdd = switch -Regex ($task.Recurrence) {
            '(\d+)m$' { [int64]$matches[1] * 60 }
            '(\d+)h$' { [int64]$matches[1] * 3600 }
            '(\d+)d$' { [int64]$matches[1] * 86400 }
            default { 0 }
        }

        if ($secondsToAdd -gt 0) {
            $unixtimeNow = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            if ([int64]$task.ScheduledTime -lt ($unixtimeNow - $secondsToAdd)) {
                $task.ScheduledTime = $unixtimeNow
            }
        }

        $nextRunUnixTime = [int64]$task.ScheduledTime + [int64]$secondsToAdd
        if ($task.Recurrence -ne 0) { $State = 'Failed - Planned' } else { $State = 'Failed' }
        Write-Information "The job is recurring, but failed. It was scheduled for $($task.ScheduledTime). The next runtime should be $nextRunUnixTime"
        Update-AzDataTableEntity -Force @Table -Entity @{
            PartitionKey  = $task.PartitionKey
            RowKey        = $task.RowKey
            Results       = "$errorMessage"
            ScheduledTime = "$nextRunUnixTime"
            TaskState     = $State
        }
        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $Tenant -tenantid $TenantInfo.customerId -message "Failed to execute task $($task.Name): $errorMessage" -sev Error -LogData (Get-CippExceptionData -Exception $_.Exception)
    }

    # For orchestrator-based commands, skip post-execution alerts as they will be handled by the orchestrator's post-execution function
    if ($Results -and $Item.Command -notin $OrchestratorBasedCommands) {
        Write-Information "Sending task results to post execution target(s): $($Task.PostExecution -join ', ')."
        Send-CIPPScheduledTaskAlert -Results $Results -TaskInfo $task -TenantFilter $Tenant -TaskType $TaskType
    }

    try {
        # For orchestrator-based commands, skip task state update as it will be handled by post-execution
        if ($Item.Command -in $OrchestratorBasedCommands) {
            Write-Information "Command $($Item.Command) is orchestrator-based. Skipping task state update - will be handled by post-execution."
            # Update task state to 'Running' to indicate orchestration is in progress
            Update-AzDataTableEntity -Force @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                Results      = 'Orchestration in progress'
                TaskState    = 'Processing'
            }
        } elseif ($task.Recurrence -eq '0' -or [string]::IsNullOrEmpty($task.Recurrence) -or $Trigger.ExecutionMode.value -eq 'once' -or $Trigger.ExecutionMode -eq 'once') {
            Write-Information 'Recurrence empty or 0. Task is not recurring. Setting task state to completed.'
            Update-AzDataTableEntity -Force @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                Results      = "$StoredResults"
                TaskState    = 'Completed'
            }
        } else {
            #if recurrence is just a number, add it in days.
            if ($task.Recurrence -match '^\d+$') {
                $task.Recurrence = $task.Recurrence + 'd'
            }
            $secondsToAdd = switch -Regex ($task.Recurrence) {
                '(\d+)m$' { [int64]$matches[1] * 60 }
                '(\d+)h$' { [int64]$matches[1] * 3600 }
                '(\d+)d$' { [int64]$matches[1] * 86400 }
                default { 0 }
            }

            if ($secondsToAdd -gt 0) {
                $unixtimeNow = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
                if ([int64]$task.ScheduledTime -lt ($unixtimeNow - $secondsToAdd)) {
                    $task.ScheduledTime = $unixtimeNow
                }
            }

            $nextRunUnixTime = [int64]$task.ScheduledTime + [int64]$secondsToAdd
            Write-Information "The job is recurring. It was scheduled for $($task.ScheduledTime). The next runtime should be $nextRunUnixTime"
            Update-AzDataTableEntity -Force @Table -Entity @{
                PartitionKey  = $task.PartitionKey
                RowKey        = $task.RowKey
                Results       = "$StoredResults"
                TaskState     = 'Planned'
                ScheduledTime = "$nextRunUnixTime"
            }
        }
    } catch {
        Write-Warning "Failed to update task state: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }
    if ($TaskType -ne 'Alert') {
        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $Tenant -tenantid $TenantInfo.customerId -message "Successfully executed task: $($task.Name)" -sev Info
    }
    Remove-Variable -Name ScheduledTaskId -Scope Script -ErrorAction SilentlyContinue
    return 'Task Completed Successfully.'
}
