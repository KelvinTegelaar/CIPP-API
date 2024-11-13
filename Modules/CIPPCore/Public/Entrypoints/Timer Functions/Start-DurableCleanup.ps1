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
        [int]$MaxDuration = 3600
    )

    $WarningPreference = 'SilentlyContinue'
    $StorageContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
    $TargetTime = (Get-Date).ToUniversalTime().AddSeconds(-$MaxDuration)
    $Context = New-AzDataTableContext -ConnectionString $env:AzureWebJobsStorage
    $InstancesTables = Get-AzDataTable -Context $Context | Where-Object { $_ -match 'Instances' }

    $CleanupCount = 0
    $QueueCount = 0
    foreach ($Table in $InstancesTables) {
        $Table = Get-CippTable -TableName $Table
        $ClearQueues = $false
        $FunctionName = $Table.TableName -replace 'Instances', ''
        $Orchestrators = Get-CIPPAzDataTableEntity @Table -Filter "RuntimeStatus eq 'Running'" | Select-Object * -ExcludeProperty Input
        $LongRunningOrchestrators = $Orchestrators | Where-Object { $_.CreatedTime.DateTime -lt $TargetTime }
        foreach ($Orchestrator in $LongRunningOrchestrators) {
            $CreatedTime = [DateTime]::SpecifyKind($Orchestrator.CreatedTime.DateTime, [DateTimeKind]::Utc)
            $TimeSpan = New-TimeSpan -Start $CreatedTime -End (Get-Date).ToUniversalTime()
            $RunningDuration = [math]::Round($TimeSpan.TotalMinutes, 2)
            Write-Information "Orchestrator: $($Orchestrator.PartitionKey), created: $CreatedTime, running for: $RunningDuration minutes"
            $ClearQueues = $true
            if ($PSCmdlet.ShouldProcess($_.PartitionKey, 'Terminate Orchestrator')) {
                $Orchestrator = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$($Orchestrator.PartitionKey)'"
                $Orchestrator.RuntimeStatus = 'Failed'
                Update-AzDataTableEntity @Table -Entity $Orchestrator
                $CleanupCount++
            }
        }

        if ($ClearQueues) {
            $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount, QueueClient
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
    Write-Information "Cleanup complete. $CleanupCount orchestrators were terminated. $QueueCount queues were cleared."
}
