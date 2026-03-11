function Get-CIPPAzStorageQueueAnalysis {
    <#
    .SYNOPSIS
        Analyses queue messages for DurableTask activity patterns.
    .DESCRIPTION
        Accepts queue messages from the pipeline or fetches them by queue name.
        Detects DurableTask.AzureStorage.MessageData messages and parses the nested
        Input JSON to produce a breakdown by tenant, task name, function name, and
        orchestration instance. Non-DurableTask messages are counted but not parsed.
    .PARAMETER InputObject
        Queue message objects from Get-CIPPAzStorageQueueMessage.
    .PARAMETER Name
        Queue name to fetch messages from directly (uses Get-CIPPAzStorageQueueMessage).
    .PARAMETER NumberOfMessages
        Passed through to Get-CIPPAzStorageQueueMessage when -Name is used.
    .PARAMETER ConnectionString
        Azure Storage connection string. Defaults to $env:AzureWebJobsStorage
    .PARAMETER RawTasks
        If set, includes the full flat task list in the output.
    .EXAMPLE
        Get-CIPPAzStorageQueueAnalysis -Name 'cipp23l35proc-workitems'
    .EXAMPLE
        Get-CIPPAzStorageQueueMessage -Name 'cipp23l35proc-workitems' | Get-CIPPAzStorageQueueAnalysis
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [int]$NumberOfMessages,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByName')]
        [string]$ConnectionString = $env:AzureWebJobsStorage,

        [Parameter(Mandatory = $false)]
        [switch]$RawTasks
    )

    begin {
        $allMessages = [System.Collections.Generic.List[object]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            foreach ($msg in $InputObject) { $allMessages.Add($msg) }
        }
    }

    end {
        # Fetch messages if called by name
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $fetchParams = @{ Name = $Name; ConnectionString = $ConnectionString }
            if ($PSBoundParameters.ContainsKey('NumberOfMessages')) { $fetchParams['NumberOfMessages'] = $NumberOfMessages }
            $fetched = Get-CIPPAzStorageQueueMessage @fetchParams
            foreach ($msg in @($fetched)) { $allMessages.Add($msg) }
        }

        $durableMessages  = 0
        $unknownMessages  = 0
        $tasks            = [System.Collections.Generic.List[object]]::new()
        $byTenant         = @{}
        $byTaskName       = @{}
        $byFunctionName   = @{}
        $byOrchestration  = @{}
        $oldestTime       = $null
        $newestTime       = $null

        foreach ($msg in $allMessages) {
            # Track insertion time range
            if ($msg.InsertionTime) {
                try {
                    $t = [System.DateTimeOffset]::Parse($msg.InsertionTime)
                    if ($null -eq $oldestTime -or $t -lt $oldestTime) { $oldestTime = $t }
                    if ($null -eq $newestTime -or $t -gt $newestTime) { $newestTime = $t }
                } catch { }
            }

            $msgData = $msg.Message
            $isDurable = $msgData -and
                         $msgData.PSObject.Properties['$type'] -and
                         $msgData.'$type' -like 'DurableTask.AzureStorage.MessageData*'

            if (-not $isDurable) {
                $unknownMessages++
                continue
            }

            $durableMessages++
            $event     = $msgData.TaskMessage?.Event
            $orchInst  = $msgData.TaskMessage?.OrchestrationInstance

            # Parse the Input field (JSON string inside the message)
            $inputTasks = @()
            if ($event -and $event.Input) {
                try {
                    if (Test-Json -Json $event.Input -ErrorAction SilentlyContinue) {
                        $inputTasks = @($event.Input | ConvertFrom-Json -Depth 10)
                    }
                } catch { }
            }

            foreach ($task in $inputTasks) {
                $tenant   = $task.TenantFilter
                $taskName = $task.Name
                $funcName = $task.FunctionName
                $queueId  = $task.QueueId
                $orchId   = $orchInst?.InstanceId

                # Aggregate counts
                if ($tenant)   { $byTenant[$tenant]     = ($byTenant[$tenant] ?? 0) + 1 }
                if ($taskName) { $byTaskName[$taskName]  = ($byTaskName[$taskName] ?? 0) + 1 }
                if ($funcName) { $byFunctionName[$funcName] = ($byFunctionName[$funcName] ?? 0) + 1 }

                # Per-orchestration breakdown
                if ($orchId) {
                    if (-not $byOrchestration.ContainsKey($orchId)) {
                        $byOrchestration[$orchId] = [PSCustomObject]@{
                            InstanceId   = $orchId
                            ExecutionId  = $orchInst?.ExecutionId
                            Tenants      = [System.Collections.Generic.HashSet[string]]::new()
                            TaskCount    = 0
                            TaskNames    = [System.Collections.Generic.List[string]]::new()
                        }
                    }
                    $byOrchestration[$orchId].TaskCount++
                    if ($tenant)   { [void]$byOrchestration[$orchId].Tenants.Add($tenant) }
                    if ($taskName) { $byOrchestration[$orchId].TaskNames.Add($taskName) }
                }

                $tasks.Add([PSCustomObject]@{
                    MessageId      = $msg.MessageId
                    InsertionTime  = $msg.InsertionTime
                    DequeueCount   = $msg.DequeueCount
                    SequenceNumber = $msgData.SequenceNumber
                    Episode        = $msgData.Episode
                    TenantFilter   = $tenant
                    TaskName       = $taskName
                    FunctionName   = $funcName
                    QueueId        = $queueId
                    OrchestrationInstanceId = $orchId
                    EventTimestamp = $event?.Timestamp
                })
            }
        }

        # Sort summary tables descending by count
        $tenantSummary   = $byTenant.GetEnumerator()       | Sort-Object Value -Descending | ForEach-Object { [PSCustomObject]@{ Tenant = $_.Key; Count = $_.Value } }
        $taskSummary     = $byTaskName.GetEnumerator()     | Sort-Object Value -Descending | ForEach-Object { [PSCustomObject]@{ TaskName = $_.Key; Count = $_.Value } }
        $funcSummary     = $byFunctionName.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [PSCustomObject]@{ FunctionName = $_.Key; Count = $_.Value } }
        $orchSummary     = $byOrchestration.Values         | Sort-Object TaskCount -Descending | ForEach-Object {
            [PSCustomObject]@{
                InstanceId  = $_.InstanceId
                ExecutionId = $_.ExecutionId
                Tenants     = @($_.Tenants)
                TaskCount   = $_.TaskCount
            }
        }

        $result = [PSCustomObject]@{
            TotalMessages       = $allMessages.Count
            DurableTaskMessages = $durableMessages
            OtherMessages       = $unknownMessages
            OldestMessage       = if ($oldestTime) { $oldestTime.ToString('u') } else { $null }
            NewestMessage       = if ($newestTime) { $newestTime.ToString('u') } else { $null }
            ByTenant            = $tenantSummary
            ByTaskName          = $taskSummary
            ByFunctionName      = $funcSummary
            ByOrchestration     = $orchSummary
        }

        if ($RawTasks) { $result | Add-Member -NotePropertyName Tasks -NotePropertyValue $tasks.ToArray() }

        $result
    }
}
