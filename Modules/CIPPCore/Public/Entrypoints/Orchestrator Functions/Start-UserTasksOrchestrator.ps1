function Start-UserTasksOrchestrator {
    <#
    .SYNOPSIS
    Start the User Tasks Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Table = Get-CippTable -tablename 'ScheduledTasks'
    $1HourAgo = (Get-Date).AddHours(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "TaskState eq 'Planned' or TaskState eq 'Failed - Planned' or (TaskState eq 'Running' and Timestamp lt datetime'$1HourAgo')"
    $tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    $Batch = [System.Collections.Generic.List[object]]::new()
    $TenantList = Get-Tenants -IncludeErrors
    foreach ($task in $tasks) {
        $tenant = $task.Tenant
        $currentUnixTime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        if ($currentUnixTime -ge $task.ScheduledTime) {
            try {
                $null = Update-AzDataTableEntity -Force @Table -Entity @{
                    PartitionKey = $task.PartitionKey
                    RowKey       = $task.RowKey
                    ExecutedTime = "$currentUnixTime"
                    TaskState    = 'Planned'
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
                    $ExcludedTenants = $task.excludedTenants -split ','
                    Write-Host "Excluded Tenants from this task: $ExcludedTenants"
                    $AllTenantCommands = foreach ($Tenant in $TenantList | Where-Object { $_.defaultDomainName -notin $ExcludedTenants }) {
                        $NewParams = $task.Parameters.Clone()
                        if ((Get-Command $task.Command).Parameters.TenantFilter) {
                            $NewParams.TenantFilter = $Tenant.defaultDomainName
                        }
                        [pscustomobject]@{
                            Command      = $task.Command
                            Parameters   = $NewParams
                            TaskInfo     = $task
                            FunctionName = 'ExecScheduledCommand'
                        }
                    }
                    $Batch.AddRange($AllTenantCommands)
                } elseif ($task.TenantGroup) {
                    # Handle tenant groups - expand group to individual tenants
                    try {
                        $TenantGroupObject = $task.TenantGroup | ConvertFrom-Json
                        Write-Host "Expanding tenant group: $($TenantGroupObject.label) with ID: $($TenantGroupObject.value)"

                        # Create a tenant filter object for expansion
                        $TenantFilterForExpansion = @([PSCustomObject]@{
                                type  = 'Group'
                                value = $TenantGroupObject.value
                                label = $TenantGroupObject.label
                            })

                        # Expand the tenant group to individual tenants
                        $ExpandedTenants = Expand-CIPPTenantGroups -TenantFilter $TenantFilterForExpansion

                        $ExcludedTenants = $task.excludedTenants -split ','
                        Write-Host "Excluded Tenants from this task: $ExcludedTenants"

                        $GroupTenantCommands = foreach ($ExpandedTenant in $ExpandedTenants | Where-Object { $_.value -notin $ExcludedTenants }) {
                            $NewParams = $task.Parameters.Clone()
                            if ((Get-Command $task.Command).Parameters.TenantFilter) {
                                $NewParams.TenantFilter = $ExpandedTenant.value
                            }
                            [pscustomobject]@{
                                Command      = $task.Command
                                Parameters   = $NewParams
                                TaskInfo     = $task
                                FunctionName = 'ExecScheduledCommand'
                            }
                        }
                        $Batch.AddRange($GroupTenantCommands)
                    } catch {
                        Write-Host "Error expanding tenant group: $($_.Exception.Message)"
                        Write-LogMessage -API 'Scheduler_UserTasks' -tenant $tenant -message "Failed to expand tenant group for task $($task.Name): $($_.Exception.Message)" -sev Error

                        # Fall back to treating as single tenant
                        if ((Get-Command $task.Command).Parameters.TenantFilter) {
                            $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                        }
                        $Batch.Add($ScheduledCommand)
                    }
                } else {
                    # Handle single tenant
                    if ((Get-Command $task.Command).Parameters.TenantFilter) {
                        $ScheduledCommand.Parameters['TenantFilter'] = $task.Tenant
                    }
                    $Batch.Add($ScheduledCommand)
                }
            } catch {
                $errorMessage = $_.Exception.Message

                $null = Update-AzDataTableEntity -Force @Table -Entity @{
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
        # Create queue entry
        $Queue = New-CippQueueEntry -Name 'Scheduled Tasks' -TotalTasks ($Batch | Measure-Object).Count
        $QueueId = $Queue.RowKey
        $Batch = $Batch | Select-Object *, @{Name = 'QueueId'; Expression = { $QueueId } }, @{Name = 'QueueName'; Expression = { '{0} - {1}' -f $_.TaskInfo.Name, ($_.TaskInfo.Tenant -ne 'AllTenants' ? $_.TaskInfo.Tenant : $_.Parameters.TenantFilter) } }

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'UserTaskOrchestrator'
            Batch            = @($Batch)
            SkipLog          = $true
        }
        #Write-Host ($InputObject | ConvertTo-Json -Depth 10)

        if ($PSCmdlet.ShouldProcess('Start-UserTasksOrchestrator', 'Starting User Tasks Orchestrator')) {
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
        }
    }
}
