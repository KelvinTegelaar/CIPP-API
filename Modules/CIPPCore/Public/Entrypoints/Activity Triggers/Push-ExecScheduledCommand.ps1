function Push-ExecScheduledCommand {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)
    $item = $Item | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    Write-Host "We are going to be running a scheduled task: $($Item.TaskInfo | ConvertTo-Json -Depth 10)"

    $Table = Get-CippTable -tablename 'ScheduledTasks'
    $task = $Item.TaskInfo
    $commandParameters = $Item.Parameters | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

    $tenant = $Item.Parameters['TenantFilter']
    Write-Host "Started Task: $($Item.Command) for tenant: $tenant"
    try {
        try {
            Write-Host "Starting task: $($Item.Command) with parameters: $($commandParameters | ConvertTo-Json)"
            $results = & $Item.Command @commandParameters
        } catch {
            $results = "Task Failed: $($_.Exception.Message)"
        }

        Write-Host 'ran the command. Processing results'
        if ($item.command -like 'Get-CIPPAlert*') {
            $results = @($results)
            $TaskType = 'Alert'
        } else {
            $TaskType = 'Scheduled Task'
            if ($results -is [String]) {
                $results = @{ Results = $results }
            }
            if ($results -is [array] -and $results[0] -is [string]) {
                $results = $results | Where-Object { $_ -is [string] }
                $results = $results | ForEach-Object { @{ Results = $_ } }
            }

            if ($results -is [string]) {
                $StoredResults = $results
            } else {
                $results = $results | Select-Object * -ExcludeProperty RowKey, PartitionKey
                $StoredResults = $results | ConvertTo-Json -Compress -Depth 20 | Out-String
            }
        }

        if ($StoredResults.Length -gt 64000 -or $task.Tenant -eq 'AllTenants') {
            $StoredResults = @{ Results = 'The results for this query are too long to store in this table, or the query was meant for All Tenants. Please use the options to send the results to another target to be able to view the results. ' } | ConvertTo-Json -Compress
        }
    } catch {
        $errorMessage = $_.Exception.Message
        if ($task.Recurrence -ne 0) { $State = 'Failed - Planned' } else { $State = 'Failed' }
        Update-AzDataTableEntity @Table -Entity @{
            PartitionKey = $task.PartitionKey
            RowKey       = $task.RowKey
            Results      = "$errorMessage"
            TaskState    = $State
        }
        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Failed to execute task $($task.Name): $errorMessage" -sev Error -LogData (Get-CippExceptionData -Exception $_.Exception)
    }
    Write-Host 'Sending task results to target. Updating the task state.'

    if ($Results) {
        $TableDesign = '<style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style>'
        $FinalResults = if ($results -is [array] -and $results[0] -is [string]) { $Results | ConvertTo-Html -Fragment -Property @{ l = 'Text'; e = { $_ } } } else { $Results | ConvertTo-Html -Fragment }
        $HTML = $FinalResults -replace '<table>', "This alert is for tenant $tenant. <br /><br /> $TableDesign<table class=blueTable>" | Out-String
        $title = "$TaskType - $tenant - $($task.Name)"
        Write-Host 'Scheduler: Sending the results to the target.'
        Write-Host "The content of results is: $Results"
        switch -wildcard ($task.PostExecution) {
            '*psa*' { Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML -TenantFilter $tenant }
            '*email*' { Send-CIPPAlert -Type 'email' -Title $title -HTMLContent $HTML -TenantFilter $tenant }
            '*webhook*' {
                $Webhook = [PSCustomObject]@{
                    'Tenant'   = $tenant
                    'TaskInfo' = $Item.TaskInfo
                    'Results'  = $Results
                }
                Send-CIPPAlert -Type 'webhook' -Title $title -JSONContent $($Webhook | ConvertTo-Json -Depth 20)
            }
        }
    }
    Write-Host 'Sent the results to the target. Updating the task state.'

    if ($task.Recurrence -eq '0' -or [string]::IsNullOrEmpty($task.Recurrence)) {
        Write-Host 'Recurrence empty or 0. Task is not recurring. Setting task state to completed.'
        Update-AzDataTableEntity @Table -Entity @{
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
            default { throw "Unsupported recurrence format: $($task.Recurrence)" }
        }

        if ($secondsToAdd -gt 0) {
            $unixtimeNow = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            if ([int64]$task.ScheduledTime -lt ($unixtimeNow - $secondsToAdd)) {
                $task.ScheduledTime = $unixtimeNow
            }
        }

        $nextRunUnixTime = [int64]$task.ScheduledTime + [int64]$secondsToAdd
        Write-Host "The job is recurring. It was scheduled for $($task.ScheduledTime). The next runtime should be $nextRunUnixTime"
        Update-AzDataTableEntity @Table -Entity @{
            PartitionKey  = $task.PartitionKey
            RowKey        = $task.RowKey
            Results       = "$StoredResults"
            TaskState     = 'Planned'
            ScheduledTime = "$nextRunUnixTime"
        }
    }
    if ($TaskType -ne 'Alert') {
        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Successfully executed task: $($task.Name)" -sev Info
    }
}
