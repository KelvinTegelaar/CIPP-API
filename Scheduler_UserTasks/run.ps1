param($Timer)

$Table = Get-CippTable -tablename 'ScheduledTasks'
$Filter = "TaskState eq 'Planned' or TaskState eq 'Failed - Planned'"
$tasks = Get-AzDataTableEntity @Table -Filter $Filter
foreach ($task in $tasks) {
    $tenant = $task.Tenant
    $currentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date "1/1/1970")).TotalSeconds
    if ($currentUnixTime -ge $task.ScheduledTime) {
        try {
            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                ExecutedTime = "$currentUnixTime"
                TaskState    = 'Running'
            }
            $task.Parameters = $task.Parameters | ConvertFrom-Json -AsHashtable

            if (!$task.Parameters) { $task.Parameters = @{} }
            $ScheduledCommand = [pscustomobject]@{
                Command    = $task.Command
                Parameters = $task.Parameters 
                TaskInfo   = $task
            }

            if ($task.Tenant -eq "AllTenants") {
                $Results = Get-Tenants | ForEach-Object {
                    $ScheduledCommand.Parameters['TenantFilter'] = $_.defaultDomainName
                    Push-OutputBinding -Name Msg -Value $ScheduledCommand
                }
            }
            else {
                $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                $Results = Push-OutputBinding -Name Msg -Value $ScheduledCommand
            }

        }
        catch {
            $errorMessage = $_.Exception.Message

            Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                Results      = "$errorMessage"
                ExecutedTime = "$currentUnixTime"
                TaskState    = 'Failed'
            }
            Write-LogMessage -API "Scheduler_UserTasks" -tenant $tenant -message "Failed to execute task $($task.Name): $errorMessage" -sev Error
        }
    }
}