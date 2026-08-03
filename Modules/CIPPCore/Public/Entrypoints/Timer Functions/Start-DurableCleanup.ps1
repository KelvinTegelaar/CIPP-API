function Start-DurableCleanup {
    <#
    .SYNOPSIS
    Start the durable cleanup process.

    .DESCRIPTION
    Look for orchestrators running for more than the specified time and terminate them. Also, clear any queues that have items for that function app.

    .PARAMETER MaxDuration
    The maximum duration an orchestrator can run before being terminated.

    .FUNCTIONALITY
    Internal
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [int]$MaxDuration = 86400
    )

    if $env:CIPPNG -eq 'true' {
        return
    }

    $WarningPreference = 'SilentlyContinue'
    $TargetTime = (Get-Date).ToUniversalTime().AddSeconds(-$MaxDuration)
    $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage
    $InstancesTables = Get-AzDataTable -Context $Context | Where-Object { $_ -match 'Instances' }

    $CleanupCount = 0
    $QueueCount = 0

    $FunctionsWithLongRunningOrchestrators = [System.Collections.Generic.List[object]]::new()
    $NonDeterministicOrchestrators = [System.Collections.Generic.List[object]]::new()

    foreach ($TableName in $InstancesTables) {
        $Table = Get-CippTable -TableName $TableName
        $FunctionName = $TableName -replace 'Instances', ''
        # Limit query to avoid memory issues with large datasets
        $Orchestrators = Get-CIPPAzDataTableEntity @Table -Filter "RuntimeStatus eq 'Running'" -First 1000 | Select-Object * -ExcludeProperty Input
        $Queues = Get-CIPPAzStorageQueue -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount, QueueClient
        $LongRunningOrchestrators = $Orchestrators | Where-Object { $_.CreatedTime.DateTime -lt $TargetTime }

        if ($LongRunningOrchestrators.Count -gt 0) {
            $FunctionsWithLongRunningOrchestrators.Add(@{'FunctionName' = $FunctionName })
            foreach ($Orchestrator in $LongRunningOrchestrators) {
                $CreatedTime = [DateTime]::SpecifyKind($Orchestrator.CreatedTime.DateTime, [DateTimeKind]::Utc)
                $TimeSpan = New-TimeSpan -Start $CreatedTime -End (Get-Date).ToUniversalTime()
                $RunningDuration = [math]::Round($TimeSpan.TotalMinutes, 2)
                Write-Information "Orchestrator: $($Orchestrator.PartitionKey), created: $CreatedTime, running for: $RunningDuration minutes"
                if ($PSCmdlet.ShouldProcess($Orchestrator.PartitionKey, 'Terminate Orchestrator')) {
                    # Update in-place instead of re-fetching (eliminates N+1 query)
                    $Orchestrator.RuntimeStatus = 'Failed'
                    if ($Orchestrator.PSObject.Properties.Name -contains 'CustomStatus') {
                        $Orchestrator.CustomStatus = "Terminated by Durable Cleanup - Exceeded max duration of $MaxDuration seconds"
                    } else {
                        $Orchestrator | Add-Member -MemberType NoteProperty -Name CustomStatus -Value "Terminated by Durable Cleanup - Exceeded max duration of $MaxDuration seconds"
                    }
                    try {
                        Update-AzDataTableEntity @Table -Entity $Orchestrator -ErrorAction Stop
                        $CleanupCount++
                    } catch {
                        # Handle concurrent modification - entity may have been updated/deleted
                        if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound|Precondition Failed') {
                            Write-Warning "Failed to update orchestrator $($Orchestrator.PartitionKey): $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        $NonDeterministicList = $Orchestrators | Where-Object { $_.Output -match 'Non-Deterministic workflow detected' }
        if ($NonDeterministicList.Count -gt 0) {
            $NonDeterministicOrchestrators.Add(@{'FunctionName' = $FunctionName })
            foreach ($Orchestrator in $NonDeterministicList) {
                Write-Information "Orchestrator: $($Orchestrator.PartitionKey) is Non-Deterministic"
                if ($PSCmdlet.ShouldProcess($Orchestrator.PartitionKey, 'Terminate Orchestrator')) {
                    # Update in-place instead of re-fetching (eliminates N+1 query)
                    $Orchestrator.RuntimeStatus = 'Failed'
                    if ($Orchestrator.PSObject.Properties.Name -contains 'CustomStatus') {
                        $Orchestrator.CustomStatus = 'Terminated by Durable Cleanup - Non-Deterministic workflow detected'
                    } else {
                        $Orchestrator | Add-Member -MemberType NoteProperty -Name CustomStatus -Value 'Terminated by Durable Cleanup - Non-Deterministic workflow detected'
                    }
                    try {
                        Update-AzDataTableEntity @Table -Entity $Orchestrator -ErrorAction Stop
                        $CleanupCount++
                    } catch {
                        # Handle concurrent modification - entity may have been updated/deleted
                        if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound|Precondition Failed') {
                            Write-Warning "Failed to update orchestrator $($Orchestrator.PartitionKey): $($_.Exception.Message)"
                        }
                    }
                }
            }
        }

        if (($LongRunningOrchestrators.Count -gt 0 -or $NonDeterministicList.Count -gt 0) -and $Queues.ApproximateMessageCount -gt 0) {
            $RunningQueues = $Queues | Where-Object { $_.ApproximateMessageCount -gt 0 }
            foreach ($Queue in $RunningQueues) {
                Write-Information "- Removing queue: $($Queue.Name), message count: $($Queue.ApproximateMessageCount)"
                if ($PSCmdlet.ShouldProcess($Queue.Name, 'Clear Queue')) {
                    $Queue.QueueClient.ClearMessagesAsync() | Out-Null
                }
                $QueueCount++
            }
        }
    }

    if ($CleanupCount -gt 0 -or $QueueCount -gt 0) {
        Write-LogMessage -api 'Durable Cleanup' -message "$CleanupCount orchestrators were terminated. $QueueCount queues were cleared." -sev 'Info' -LogData $FunctionsWithLongRunningOrchestrators
    }

    # Purge completed/failed/terminated durable function history older than retention period
    # This reduces storage write/read overhead from accumulating history rows
    $PurgeCount = 0
    $PurgeRetentionHours = 24
    $PurgeCutoff = (Get-Date).ToUniversalTime().AddHours(-$PurgeRetentionHours)

    foreach ($TableName in $InstancesTables) {
        $Table = Get-CippTable -TableName $TableName
        $HistoryTableName = $TableName -replace 'Instances', 'History'

        # Purge completed/failed/terminated instances older than retention period
        $CompletedFilter = "(RuntimeStatus eq 'Completed' or RuntimeStatus eq 'Failed' or RuntimeStatus eq 'Terminated') and Timestamp lt datetime'{0}'" -f $PurgeCutoff.ToString('yyyy-MM-ddTHH:mm:ssZ')
        try {
            $StaleInstances = Get-CIPPAzDataTableEntity @Table -Filter $CompletedFilter -Property PartitionKey, RowKey, ETag -First 500
            if ($StaleInstances -and @($StaleInstances).Count -gt 0) {
                Remove-CIPPAzDataTableEntity @Table -Entity $StaleInstances -Force -ErrorAction Stop | Out-Null
                $PurgeCount += @($StaleInstances).Count
            }
        } catch {
            if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound') {
                Write-Warning "Failed to purge instances from $TableName : $($_.Exception.Message)"
            }
        }

        # Purge corresponding history table entries
        try {
            $HistoryTable = Get-CippTable -TableName $HistoryTableName
            $HistoryFilter = "Timestamp lt datetime'{0}'" -f $PurgeCutoff.ToString('yyyy-MM-ddTHH:mm:ssZ')
            $StaleHistory = Get-CIPPAzDataTableEntity @HistoryTable -Filter $HistoryFilter -Property PartitionKey, RowKey, ETag -First 1000
            if ($StaleHistory -and @($StaleHistory).Count -gt 0) {
                Remove-CIPPAzDataTableEntity @HistoryTable -Entity $StaleHistory -Force -ErrorAction Stop | Out-Null
                $PurgeCount += @($StaleHistory).Count
            }
        } catch {
            # History table may not exist for all function apps, ignore errors
            if ($_.Exception.Message -notmatch 'does not exist|ResourceNotFound|TableNotFound') {
                Write-Warning "Failed to purge history from $HistoryTableName : $($_.Exception.Message)"
            }
        }
    }

    if ($PurgeCount -gt 0) {
        Write-Information "Purged $PurgeCount stale durable function history entries (older than $PurgeRetentionHours hours)"
    }

    Write-Information "Durable cleanup complete. $CleanupCount orchestrators were terminated. $QueueCount queues were cleared. $PurgeCount history entries purged."
}
