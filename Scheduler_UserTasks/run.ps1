param($Timer)

$Table = Get-CippTable -tablename 'ScheduledTasks'
$Filter = "TaskState eq 'Planned' or TaskState eq 'Failed - Planned'"
$tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter
$Batch = foreach ($task in $tasks) {
    $tenant = $task.Tenant
    $currentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
    if ($currentUnixTime -ge $task.ScheduledTime) {
        try {
            $null = Update-AzDataTableEntity @Table -Entity @{
                PartitionKey = $task.PartitionKey
                RowKey       = $task.RowKey
                ExecutedTime = "$currentUnixTime"
                TaskState    = 'Running'
            }
            $task.Parameters = $task.Parameters | ConvertFrom-Json -AsHashtable
            $task.AdditionalProperties = $task.AdditionalProperties | ConvertFrom-Json

            if (!$task.Parameters) { $task.Parameters = @{} }
            $ScheduledCommand = [pscustomobject]@{
                Command      = $task.Command
                Parameters   = $task.Parameters
                TaskInfo     = $task
                FunctionName = 'ExecScheduledCommand'
            }

            if ($task.Tenant -eq 'AllTenants') {
                Get-Tenants | ForEach-Object {
                    $ScheduledCommand.Parameters['TenantFilter'] = $_.defaultDomainName
                    $ScheduledCommand
                    #Push-OutputBinding -Name Msg -Value $ScheduledCommand
                }
            } else {
                $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                $ScheduledCommand
                #$Results = Push-OutputBinding -Name Msg -Value $ScheduledCommand
            }
        } catch {
            $errorMessage = $_.Exception.Message

            $null = Update-AzDataTableEntity @Table -Entity @{
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
if (($Batch | Measure-Object).Count -gt 0) {
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'UserTaskOrchestrator'
        Batch            = @($Batch)
        SkipLog          = $true
    }
    #Write-Host ($InputObject | ConvertTo-Json)
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
    Write-Host "Started orchestration with ID = '$InstanceId'"
}