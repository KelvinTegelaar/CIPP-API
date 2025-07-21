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

    Write-Information "Started Task: $($Item.Command) for tenant: $Tenant"
    try {

        try {
            Write-Information "Starting task: $($Item.Command) with parameters: $($commandParameters | ConvertTo-Json)"
            $results = & $Item.Command @commandParameters
        } catch {
            $results = "Task Failed: $($_.Exception.Message)"
            $State = 'Failed'
        }

        Write-Information 'Ran the command. Processing results'
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
        $TableDesign = '<style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style>'
        $FinalResults = if ($results -is [array] -and $results[0] -is [string]) { $Results | ConvertTo-Html -Fragment -Property @{ l = 'Text'; e = { $_ } } } else { $Results | ConvertTo-Html -Fragment }
        $HTML = $FinalResults -replace '<table>', "This alert is for tenant $Tenant. <br /><br /> $TableDesign<table class=blueTable>" | Out-String
        $title = "$TaskType - $Tenant - $($task.Name)"
        Write-Information 'Scheduler: Sending the results to the target.'
        Write-Information "The content of results is: $Results"
        switch -wildcard ($task.PostExecution) {
            '*psa*' { Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML -TenantFilter $Tenant }
            '*email*' { Send-CIPPAlert -Type 'email' -Title $title -HTMLContent $HTML -TenantFilter $Tenant }
            '*webhook*' {
                $Webhook = [PSCustomObject]@{
                    'tenantId' = $TenantInfo.customerId
                    'Tenant'   = $Tenant
                    'TaskInfo' = $Item.TaskInfo
                    'Results'  = $Results
                }
                Send-CIPPAlert -Type 'webhook' -Title $title -TenantFilter $Tenant -JSONContent $($Webhook | ConvertTo-Json -Depth 20)
            }
        }
    }
    Write-Information 'Sent the results to the target. Updating the task state.'

    try {
        if ($task.Recurrence -eq '0' -or [string]::IsNullOrEmpty($task.Recurrence)) {
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
