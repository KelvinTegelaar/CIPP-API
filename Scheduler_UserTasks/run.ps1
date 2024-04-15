param($Timer)

$Table = Get-CippTable -tablename 'ScheduledTasks'
$Filter = "TaskState eq 'Planned' or TaskState eq 'Failed - Planned'"
$tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter
$Batch = [System.Collections.Generic.List[object]]::new()
foreach ($task in $tasks) {
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
                $AllTenantCommands = foreach ($Tenant in Get-Tenants) {
                    $NewParams = $task.Parameters.Clone()
                    $NewParams.TenantFilter = $Tenant.defaultDomainName
                    [pscustomobject]@{
                        Command      = $task.Command
                        Parameters   = $NewParams
                        TaskInfo     = $task
                        FunctionName = 'ExecScheduledCommand'
                    }
                }
                $Batch.AddRange($AllTenantCommands)
            } else {
                $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                $Batch.Add($ScheduledCommand)
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
    #Write-Host ($InputObject | ConvertTo-Json -Depth 10)
    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10)

    Write-Host "Started orchestration with ID = '$InstanceId'"
}