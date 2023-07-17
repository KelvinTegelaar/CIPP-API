param($Timer)

$Table = Get-CippTable -tablename 'ScheduledTasks'
$Filter = "Results eq 'Not Executed'"
$tasks = Get-AzDataTableEntity @Table -Filter $Filter

foreach ($task in $tasks) {
    # Check if task has not been executed yet (i.e., 'Results' is 'Not Executed')
    if ((Get-Date) -ge $task.ExpectedRunTime) {
        try {
            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey = $task.RowKey
                TaskState = 'Running'
                # Update other properties as needed
            }

            $results = Invoke-Command -ScriptBlock ([ScriptBlock]::Create($task.Command)) -ArgumentList $task.Parameters

            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey = $task.RowKey
                Results = "$results"
                TaskState = 'Completed'
                # Update other properties as needed
            }

            Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Successfully executed task: $($task.RowKey)" -sev Info
        }
        catch {
            $errorMessage = $_.Exception.Message

            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey = $task.RowKey
                Results = "$errorMessage"
                TaskState = 'Failed'
                # Update other properties as needed
            }

            Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Failed to execute task: $errorMessage" -sev Error
        }
    }
}