param($Timer)

$Table = Get-CippTable -tablename 'ScheduledTasks'
$Filter = "Results eq 'Not Executed'"
$tasks = Get-AzDataTableEntity @Table -Filter $Filter

foreach ($task in $tasks) {
    if ((Get-Date) -ge $task.ExpectedRunTime) {
        try {
            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                TaskState    = 'Running'
            }
            #todo tomorrow: Replace this with a queue so each task can be run in parallel
            #todo: Set tenant filter as static object
            if ($task.Tenant -eq "AllTenants") {
                Get-Tenants | ForEach-Object {
                    $results = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($task.Command)) -ArgumentList $task.Parameters
                }
            }
            else {
                $results = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($task.Command)) -ArgumentList $task.Parameters
            }

            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                Results      = "$results"
                TaskState    = 'Completed'
            }
            #check $task.PostExecution for which alerts to send
            $TableDesign = "<style>table.blueTable{border:1px solid #1C6EA4;background-color:#EEE;width:100%;text-align:left;border-collapse:collapse}table.blueTable td,table.blueTable th{border:1px solid #AAA;padding:3px 2px}table.blueTable tbody td{font-size:13px}table.blueTable tr:nth-child(even){background:#D0E4F5}table.blueTable thead{background:#1C6EA4;background:-moz-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:-webkit-linear-gradient(top,#5592bb 0,#327cad 66%,#1C6EA4 100%);background:linear-gradient(to bottom,#5592bb 0,#327cad 66%,#1C6EA4 100%);border-bottom:2px solid #444}table.blueTable thead th{font-size:15px;font-weight:700;color:#FFF;border-left:2px solid #D0E4F5}table.blueTable thead th:first-child{border-left:none}table.blueTable tfoot{font-size:14px;font-weight:700;color:#FFF;background:#D0E4F5;background:-moz-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:-webkit-linear-gradient(top,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);background:linear-gradient(to bottom,#dcebf7 0,#d4e6f6 66%,#D0E4F5 100%);border-top:2px solid #444}table.blueTable tfoot td{font-size:14px}table.blueTable tfoot .links{text-align:right}table.blueTable tfoot .links a{display:inline-block;background:#1C6EA4;color:#FFF;padding:2px 8px;border-radius:5px}</style>"
            $HTML = ($results | ConvertTo-Html -Fragment) -replace '<table>', "$TableDesign<table class=blueTable>" | Out-String
            $title = "Scheduled Task $($task.Name) - $($task.ExpectedRunTime)"
            switch -wildcard ($task.PostExecution) {
                "*psa*" { Send-CIPPAlert -Type 'psa' -Title $title -HTMLContent $HTML }
                "*email*" { Send-CIPPAlert -Type 'email' -Title $title -HTMLContent $HTML }
                "*webhook*" { Send-CIPPAlert -Type 'webhook' -Title $title -JSONContent $($Results | ConvertTo-Json) }            
            }
            Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Successfully executed task: $($task.RowKey)" -sev Info
        }
        catch {
            $errorMessage = $_.Exception.Message

            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                Results      = "$errorMessage"
                TaskState    = 'Failed'
                # Update other properties as needed
            }

            Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Failed to execute task: $errorMessage" -sev Error
        }
    }
}