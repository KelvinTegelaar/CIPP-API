function Invoke-ExecDurableFunctions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Request, $TriggerMetadata)

    $APIName = 'ExecDurableStats'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Collect info
    $StorageContext = New-AzStorageContext -ConnectionString $env:AzureWebJobsStorage
    $FunctionName = $env:WEBSITE_SITE_NAME

    # Get orchestrators
    $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f $FunctionName)
    $Yesterday = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Filter = "CreatedTime ge datetime'$Yesterday' or RuntimeStatus eq 'Pending' or RuntimeStatus eq 'Running'"
    $Instances = Get-CippAzDataTableEntity @InstancesTable -Filter $Filter

    switch ($Request.Query.Action) {
        'ListOrchestrators' {
            $Orchestrators = foreach ($Instance in $Instances) {
                $Json = $Instance.Input -replace '^"(.+)"$', '$1' -replace '\\"', '"'

                if ($Json -notmatch '^http' -and ![string]::IsNullOrEmpty($Json)) {
                    if (Test-Json -Json $Json -ErrorAction SilentlyContinue) {
                        $Instance.Input = $Json | ConvertFrom-Json
                        if (![string]::IsNullOrEmpty($Instance.Input.OrchestratorName)) {
                            $Instance.Name = $Instance.Input.OrchestratorName
                        }
                    } else {
                        #Write-Host $Instance.Input
                        if ($Json -match '\"OrchestratorName\":\"(.+?)\"') {
                            $Instance.Name = $Matches[1]
                        }
                        $Instance.Input = 'Invalid JSON'
                    }
                }
                $Instance
            }

            $Body = [PSCustomObject]@{
                Orchestrators = @($Orchestrators)
            }
        }
        'ListOrchestratorHistory' {
            if ($Request.Query.PartitionKey) {
                $HistoryTable = Get-CippTable -TableName ('{0}History' -f $FunctionName)
                $Filter = "PartitionKey eq '{0}'" -f $Request.Query.PartitionKey
                $History = Get-CippAzDataTableEntity @HistoryTable -Filter $Filter -Property PartitionKey, RowKey, Timestamp, EventType, Name, IsPlayed, OrchestrationStatus | Select-Object * -ExcludeProperty ETag

                $Body = [PSCustomObject]@{
                    Results = @($History)
                }
            } else {
                $Body = [PSCustomObject]@{
                    Results = @('PartitionKey is required')
                }
            }
        }
        'ListStats' {
            $OrchestratorsByStatus = $Instances | Group-Object -Property RuntimeStatus

            if ($OrchestratorsByStatus.Name -contains 'Pending') {
                $PendingOrchestrators = $OrchestratorsByStatus | Where-Object -Property Name -EQ 'Pending' | Select-Object -ExpandProperty Group
                $Pending30MinCount = $PendingOrchestrators | Where-Object { $_.CreatedTime -lt (Get-Date).AddMinutes(-30).ToUniversalTime() } | Measure-Object | Select-Object -ExpandProperty Count
            }

            $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount

            $Body = [PSCustomObject]@{
                Orchestrators     = @($OrchestratorsByStatus | Select-Object Count, Name)
                Pending30MinCount = $Pending30MinCount ?? 0
                Queues            = @($Queues)
            }
        }
        'ResetDurables' {
            try {
                $Queues = Get-AzStorageQueue -Context $StorageContext -Name ('{0}*' -f $FunctionName) | Select-Object -Property Name, ApproximateMessageCount, QueueClient

                $RunningQueues = $Queues | Where-Object { $_.ApproximateMessageCount -gt 0 }
                foreach ($Queue in $RunningQueues) {
                    Write-Information "- Removing queue: $($Queue.Name), message count: $($Queue.ApproximateMessageCount)"
                    if ($PSCmdlet.ShouldProcess($Queue.Name, 'Clear Queue')) {
                        $Queue.QueueClient.ClearMessagesAsync()
                    }
                }

                $RunningInstances = $Instances | Where-Object { $_.RuntimeStatus -eq 'Running' -or $_.RuntimeStatus -eq 'Pending' }
                if (($RunningInstances | Measure-Object).Count -gt 0) {
                    if ($PSCmdlet.ShouldProcess('Orchestrators', 'Mark Failed')) {
                        foreach ($Instance in $RunningInstances) {
                            $Instance.RuntimeStatus = 'Failed'
                            Update-AzDataTableEntity @InstancesTable -Entity $Instance
                        }
                    }
                }

                $QueueTable = Get-CippTable -TableName 'CippQueue'
                $CippQueue = Invoke-ListCippQueue
                $QueueEntities = foreach ($Queue in $CippQueue) {
                    if ($Queue.Status -eq 'Running') {
                        $Queue.TotalTasks = $Queue.CompletedTasks
                        $Queue | Select-Object -Property PartitionKey, RowKey, TotalTasks
                    }
                }
                if (($QueueEntities | Measure-Object).Count -gt 0) {
                    if ($PSCmdlet.ShouldProcess('Queues', 'Mark Failed')) {
                        Update-AzDataTableEntity @QueueTable -Entity $QueueEntities
                    }
                }

                $CippQueueTasks = Get-CippTable -TableName 'CippQueueTasks'
                $RunningTasks = Get-CIPPAzDataTableEntity @CippQueueTasks -Filter "Status eq 'Running'" -Property RowKey, PartitionKey, Status
                if (($RunningTasks | Measure-Object).Count -gt 0) {
                    if ($PSCmdlet.ShouldProcess('Tasks', 'Mark Failed')) {
                        $UpdatedTasks = foreach ($Task in $RunningTasks) {
                            $Task.Status = 'Failed'
                            $Task
                        }
                        Update-AzDataTableEntity @CippQueueTasks -Entity $UpdatedTasks
                    }
                }

                $Body = [PSCustomObject]@{
                    Message = 'Durable Queues reset successfully'
                }

            } catch {
                $Body = [PSCustomObject]@{
                    Message   = "Error resetting durables: $($_.Exception.Message)"
                    Exception = Get-CippException -Exception $_
                }
            }
        }
        'PurgeOrchestrators' {
            $HistoryTable = Get-CippTable -TableName ('{0}History' -f $FunctionName)
            if ($Request.Query.PartitionKey) {
                $HistoryEntities = Get-CIPPAzDataTableEntity @HistoryTable -Filter "PartitionKey eq '$($Request.Query.PartitionKey)'" -Property RowKey, PartitionKey
                if ($HistoryEntities) {
                    Remove-AzDataTableEntity -Force @HistoryTable -Entity $HistoryEntities
                }
                $Instance = Get-CIPPAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$($Request.Query.PartitionKey)'" -Property RowKey, PartitionKey
                if ($Instance) {
                    Remove-AzDataTableEntity -Force @InstancesTable -Entity $Instance
                }
                $Body = [PSCustomObject]@{
                    Results = 'Orchestrator {0} purged successfully' -f $Request.Query.PartitionKey
                }
            } else {
                Remove-AzDataTable @InstancesTable
                Remove-AzDataTable @HistoryTable
                $BlobContainer = '{0}-largemessages' -f $Function.Name
                if (Get-AzStorageContainer -Name $BlobContainer -Context $StorageContext -ErrorAction SilentlyContinue) {
                    Write-Information "- Removing blob container: $BlobContainer"
                    if ($PSCmdlet.ShouldProcess($BlobContainer, 'Remove Blob Container')) {
                        Remove-AzStorageContainer -Name $BlobContainer -Context $StorageContext -Confirm:$false -Force
                    }
                }
                $null = Get-CippTable -TableName ('{0}History' -f $FunctionName)
                $Body = [PSCustomObject]@{
                    Message = 'Orchestrators purged successfully'
                }
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
