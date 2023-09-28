# Input bindings are passed in via param block.
param($QueueItem, $TriggerMetadata)

$Table = Get-CippTable -tablename 'ScheduledTasks'
$task = $QueueItem.TaskInfo
$commandParameters = $QueueItem.Parameters

$tenant = $QueueItem.Parameters['TenantFilter']
Write-Host "started task"
try {
    try {
        $results = & $QueueItem.command @commandParameters
    }
    catch {
        $results = "Task Failed: $($_.Exception.Message)"
        
    }
    
    Write-Host "ran the command"
    if ($results.GetType() -eq [String]) {
        $results = @{ Results = $results }
    }
    $results = $results | Select-Object *, @{l = 'TaskInfo'; e = { $QueueItem.TaskInfo } } -ExcludeProperty RowKey, PartitionKey

    $StoredResults = $results | ConvertTo-Json -Compress -Depth 20 | Out-String
    if ($StoredResults.Length -gt 64000 -or $task.Tenant -eq "AllTenants") {
        $StoredResults = @{ Results = "The results for this query are too long to store in this table, or the query was meant for All Tenants. Please use the options to send the results to another target to be able to view the results. " } | ConvertTo-Json -Compress
    }
}
catch {
    $errorMessage = $_.Exception.Message
    if ($task.Recurrence -gt 0) { $State = 'Failed - Planned' } else { $State = 'Failed' }
    Update-AzDataTableEntity @Table -Entity @{
        PartitionKey = $task.PartitionKey
        RowKey       = $task.RowKey
        Results      = "$errorMessage"
        TaskState    = $State
    }
    Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Failed to execute task $($task.Name): $errorMessage" -sev Error
}


$TableDesign = "<style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style>"
$HTML = ($results  | Select-Object * -ExcludeProperty RowKey, PartitionKey | ConvertTo-Html -Fragment) -replace '<table>', "$TableDesign<table class=blueTable>" | Out-String
$title = "Scheduled Task $($task.Name) - $($task.ExpectedRunTime)"
Write-Host $title
switch -wildcard ($task.PostExecution) {
    "*psa*" { Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML }
    "*email*" { Send-CIPPAlert -Type 'email' -Title $title -HTMLContent $HTML }
    "*webhook*" { Send-CIPPAlert -Type 'webhook' -Title $title -JSONContent $($Results | ConvertTo-Json) }            
}

Write-Host "ran the command"

if ($task.Recurrence -le '0' -or $task.Recurrence -eq $null) {
    Update-AzDataTableEntity @Table -Entity @{
        PartitionKey = $task.PartitionKey
        RowKey       = $task.RowKey
        Results      = "$StoredResults"
        TaskState    = 'Completed'
    }
}
else {
    $nextRun = (Get-Date).AddDays($task.Recurrence)
    $nextRunUnixTime = [int64]($nextRun - (Get-Date "1/1/1970")).TotalSeconds
    Update-AzDataTableEntity @Table -Entity @{
        PartitionKey  = $task.PartitionKey
        RowKey        = $task.RowKey
        Results       = "$StoredResults"
        TaskState     = 'Planned'
        ScheduledTime = "$nextRunUnixTime"
    }
}
Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Successfully executed task: $($task.name)" -sev Info