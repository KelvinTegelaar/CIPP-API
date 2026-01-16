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

    $WarningPreference = 'SilentlyContinue'
    $TargetTime = (Get-Date).ToUniversalTime().AddSeconds(-$MaxDuration)
    $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage
    $InstancesTables = Get-AzDataTable -Context $Context | Where-Object { $_ -match 'Instances' }

    $CleanupCount = 0
    $QueueCount = 0

    $FunctionsWithLongRunningOrchestrators = [System.Collections.Generic.List[object]]::new()
    $NonDeterministicOrchestrators = [System.Collections.Generic.List[object]]::new()

    foreach ($Table in $InstancesTables) {
        $Table = Get-CippTable -TableName $Table
        $FunctionName = $Table.TableName -replace 'Instances', ''
        $Orchestrators = Get-CIPPAzDataTableEntity @Table -Filter "RuntimeStatus eq 'Running'" | Select-Object * -ExcludeProperty Input
        $Queues = Get-CIPPAzStorageQueue -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount, QueueClient
        $LongRunningOrchestrators = $Orchestrators | Where-Object { $_.CreatedTime.DateTime -lt $TargetTime }

        if ($LongRunningOrchestrators.Count -gt 0) {
            $FunctionsWithLongRunningOrchestrators.Add(@{'FunctionName' = $FunctionName })
            foreach ($Orchestrator in $LongRunningOrchestrators) {
                $CreatedTime = [DateTime]::SpecifyKind($Orchestrator.CreatedTime.DateTime, [DateTimeKind]::Utc)
                $TimeSpan = New-TimeSpan -Start $CreatedTime -End (Get-Date).ToUniversalTime()
                $RunningDuration = [math]::Round($TimeSpan.TotalMinutes, 2)
                Write-Information "Orchestrator: $($Orchestrator.PartitionKey), created: $CreatedTime, running for: $RunningDuration minutes"
                if ($PSCmdlet.ShouldProcess($_.PartitionKey, 'Terminate Orchestrator')) {
                    $Orchestrator = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Orchestrator.PartitionKey)'"
                    $Orchestrator.RuntimeStatus = 'Failed'
                    if ($Orchestrator.PSObject.Properties.Name -contains 'CustomStatus') {
                        $Orchestrator.CustomStatus = "Terminated by Durable Cleanup - Exceeded max duration of $MaxDuration seconds"
                    } else {
                        $Orchestrator | Add-Member -MemberType NoteProperty -Name CustomStatus -Value "Terminated by Durable Cleanup - Exceeded max duration of $MaxDuration seconds"
                    }
                    Update-AzDataTableEntity @Table -Entity $Orchestrator
                    $CleanupCount++
                }
            }
        }

        $NonDeterministicOrchestrators = $Orchestrators | Where-Object { $_.Output -match 'Non-Deterministic workflow detected' }
        if ($NonDeterministicOrchestrators.Count -gt 0) {
            $NonDeterministicOrchestrators.Add(@{'FunctionName' = $FunctionName })
            foreach ($Orchestrator in $NonDeterministicOrchestrators) {
                Write-Information "Orchestrator: $($Orchestrator.PartitionKey) is Non-Deterministic"
                if ($PSCmdlet.ShouldProcess($_.PartitionKey, 'Terminate Orchestrator')) {
                    $Orchestrator = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Orchestrator.PartitionKey)'"
                    $Orchestrator.RuntimeStatus = 'Failed'
                    if ($Orchestrator.PSObject.Properties.Name -contains 'CustomStatus') {
                        $Orchestrator.CustomStatus = 'Terminated by Durable Cleanup - Non-Deterministic workflow detected'
                    } else {
                        $Orchestrator | Add-Member -MemberType NoteProperty -Name CustomStatus -Value 'Terminated by Durable Cleanup - Non-Deterministic workflow detected'
                    }
                    Update-AzDataTableEntity @Table -Entity $Orchestrator
                    $CleanupCount++
                }
            }
        }

        if (($LongRunningOrchestrators.Count -gt 0 -or $NonDeterministicOrchestrators.Count -gt 0) -and $Queues.ApproximateMessageCount -gt 0) {
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

    Write-Information "Durable cleanup complete. $CleanupCount orchestrators were terminated. $QueueCount queues were cleared."
}
