function Push-ExecScheduledCommand {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)
    $item = $Item | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    Write-Information "We are going to be running a scheduled task: $($Item.TaskInfo | ConvertTo-Json -Depth 10)"

    $Table = Get-CippTable -tablename 'ScheduledTasks'
    $task = $Item.TaskInfo
    $commandParameters = $Item.Parameters | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

    # Handle tenant resolution - support both direct tenant and group-expanded tenants
    $Tenant = $Item.Parameters.TenantFilter ?? $Item.TaskInfo.Tenant

    # For tenant group tasks, the tenant will be the expanded tenant from the orchestrator
    # We don't need to expand groups here as that's handled in the orchestrator
    $TenantInfo = Get-Tenants -TenantFilter $Tenant

    $CurrentTask = Get-AzDataTableEntity @Table -Filter "PartitionKey eq '$($task.PartitionKey)' and RowKey eq '$($task.RowKey)'"
    if (!$CurrentTask) {
        Write-Information "The task $($task.Name) for tenant $($task.Tenant) does not exist in the ScheduledTasks table. Exiting."
        return
    }
    if ($CurrentTask.TaskState -eq 'Completed') {
        Write-Information "The task $($task.Name) for tenant $($task.Tenant) is already completed. Skipping execution."
        return
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
        if ($StoredResults.Length -gt 64000 -or $task.Tenant -eq 'AllTenants' -or $task.TenantGroup) {
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
    Write-Information 'Sending task results to target. Updating the task state.'

    if ($Results) {
        $TableDesign = '<style>table.adaptiveTable{border:1px solid currentColor;background-color:transparent;width:100%;text-align:left;border-collapse:collapse;opacity:0.9}table.adaptiveTable td,table.adaptiveTable th{border:1px solid currentColor;padding:8px 6px;opacity:0.8}table.adaptiveTable tbody td{font-size:13px}table.adaptiveTable tr:nth-child(even){background-color:rgba(128,128,128,0.1)}table.adaptiveTable thead{background-color:rgba(128,128,128,0.2);border-bottom:2px solid currentColor}table.adaptiveTable thead th{font-size:15px;font-weight:700;border-left:1px solid currentColor}table.adaptiveTable thead th:first-child{border-left:none}table.adaptiveTable tfoot{font-size:14px;font-weight:700;background-color:rgba(128,128,128,0.1);border-top:2px solid currentColor}table.adaptiveTable tfoot td{font-size:14px}@media (prefers-color-scheme: dark){table.adaptiveTable{opacity:0.95}table.adaptiveTable tr:nth-child(even){background-color:rgba(255,255,255,0.05)}table.adaptiveTable thead{background-color:rgba(255,255,255,0.1)}table.adaptiveTable tfoot{background-color:rgba(255,255,255,0.05)}}</style>'
        $FinalResults = if ($results -is [array] -and $results[0] -is [string]) { $Results | ConvertTo-Html -Fragment -Property @{ l = 'Text'; e = { $_ } } } else { $Results | ConvertTo-Html -Fragment }
        $HTML = $FinalResults -replace '<table>', "This alert is for tenant $Tenant. <br /><br /> $TableDesign<table class=adaptiveTable>" | Out-String

        # Add alert comment if available
        if ($task.AlertComment) {
            $HTML += "<div style='background-color: #f8f9fa; border-left: 4px solid #007bff; padding: 15px; margin: 15px 0;'><h4 style='margin-top: 0; color: #007bff;'>Alert Information</h4><p style='margin-bottom: 0;'>$($task.AlertComment)</p></div>"
        }

        $title = "$TaskType - $Tenant - $($task.Name)"
        Write-Information 'Scheduler: Sending the results to the target.'
        Write-Information "The content of results is: $Results"
        switch -wildcard ($task.PostExecution) {
            '*psa*' { Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML -TenantFilter $Tenant }
            '*email*' { Send-CIPPAlert -Type 'email' -Title $title -HTMLContent $HTML -TenantFilter $Tenant }
            '*webhook*' {
                $Webhook = [PSCustomObject]@{
                    'tenantId'     = $TenantInfo.customerId
                    'Tenant'       = $Tenant
                    'TaskInfo'     = $Item.TaskInfo
                    'Results'      = $Results
                    'AlertComment' = $task.AlertComment
                }
                Send-CIPPAlert -Type 'webhook' -Title $title -TenantFilter $Tenant -JSONContent $($Webhook | ConvertTo-Json -Depth 20)
            }
        }
    }
    Write-Information 'Sent the results to the target. Updating the task state.'

    try {
        if ($task.Recurrence -eq '0' -or [string]::IsNullOrEmpty($task.Recurrence) -or $Trigger.ExecutionMode.value -eq 'once' -or $Trigger.ExecutionMode -eq 'once') {
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
}
