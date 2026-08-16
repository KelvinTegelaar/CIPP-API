function Start-CIPPOrchestrator {
    <#
    .SYNOPSIS
        Start a CIPP orchestrator with automatic queue routing
    .DESCRIPTION
        Wrapper around Start-NewOrchestration that stores input objects in table storage
        and routes orchestration execution through the queue to avoid size limits and enable offloading.

        When called from HTTP functions: Stores input object, queues message with GUID
        When called from queue trigger with GUID: Retrieves input object, starts orchestration
        When called from queue trigger with -CallerIsQueueTrigger: Starts orchestration directly (no re-queuing)
    .PARAMETER InputObjectGuid
        GUID reference to retrieve stored input object from table (used internally by queue trigger)
    .PARAMETER InputObject
        The orchestrator input object (same structure as Start-NewOrchestration)
    .PARAMETER CallerIsQueueTrigger
        Indicates the caller is already running in a queue trigger context.
        Skips queuing and starts orchestration directly to avoid double-queuing.
    .EXAMPLE
        Start-CIPPOrchestrator -InputObject @{OrchestratorName='BPA'; Batch=@($Tenants)}
    .EXAMPLE
        Start-CIPPOrchestrator -InputObject $InputObject -CallerIsQueueTrigger
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$InputObjectGuid,

        [Parameter(Mandatory = $false)]
        [object]$InputObject,

        [switch]$CallerIsQueueTrigger
    )

    # ─── Craft runtime: push batch directly to OrchestratorService ───
    if ($env:CIPPNG -eq 'true' -and $InputObject) {
        $OrchestratorName = $InputObject.OrchestratorName ?? 'UnnamedOrchestrator'

        # QueueFunction pattern: call the function first to generate batch items
        if (-not $InputObject.Batch -and $InputObject.QueueFunction) {
            $QueueFuncName = "Push-$($InputObject.QueueFunction.FunctionName)"
            Write-Information "Craft: Calling QueueFunction '$QueueFuncName' to build batch for '$OrchestratorName'"
            $QueueItem = [PSCustomObject]$InputObject.QueueFunction
            $BatchResult = & $QueueFuncName -Item $QueueItem
            $QueueBatch = @($BatchResult | Where-Object { $null -ne $_ })
            if ($QueueBatch.Count -eq 0) {
                Write-Information "Craft: QueueFunction '$QueueFuncName' returned 0 tasks for '$OrchestratorName' - skipping"
                return "Craft-$OrchestratorName-NoTasks"
            }
            $InputObject | Add-Member -MemberType NoteProperty -Name 'Batch' -Value $QueueBatch -Force
        }

        # Include QueueId in RunName so the frontend can poll status by QueueId
        $BatchQueueId = ($InputObject.Batch | Select-Object -First 1).QueueId
        if ($BatchQueueId) {
            $OrchestratorName = "$OrchestratorName-$BatchQueueId"
        }

        $PostExecFunctionName = $null
        $PostExecParametersJson = $null
        if ($InputObject.PostExecution) {
            $PostExecFunctionName = $InputObject.PostExecution.FunctionName
            if ($InputObject.PostExecution.Parameters) {
                $PostExecParametersJson = $InputObject.PostExecution.Parameters | ConvertTo-Json -Depth 10 -Compress
            }
        }

        # Write the batch as JSON Lines — one task per line — and hand Craft the path.
        #
        # This used to be a single `ConvertTo-Json @($InputObject.Batch)`, which put the entire
        # fan-out in one string. That is what made per-task payloads so expensive: Set-CIPPDBCacheMailboxes
        # notes it directly, because every permission batch carrying a copy of all mailboxes turned a
        # 10k-mailbox tenant into 200 batches x 10k entries in ONE string. Narrowing what each batch
        # carries reduced that, but the whole-batch-as-one-string shape was the reason it mattered.
        # Serialising one task at a time means peak memory is one task, whether the run has 10 or 10,000
        # — and Craft parses it back a line at a time for the same reason.
        #
        # Depth is per task now rather than per array, so tasks get one more level than before. That can
        # only include detail that was previously truncated to a type name, never less.
        $BatchPath = Join-Path ([System.IO.Path]::GetTempPath()) "cipp-batch-$([guid]::NewGuid().ToString('N')).jsonl"
        $TaskCount = 0
        try {
            $Writer = [System.IO.StreamWriter]::new($BatchPath, $false, [System.Text.Encoding]::UTF8)
            try {
                foreach ($BatchItem in @($InputObject.Batch)) {
                    if ($null -eq $BatchItem) { continue }
                    $Writer.WriteLine((ConvertTo-Json -InputObject $BatchItem -Depth 10 -Compress))
                    $TaskCount++
                }
            } finally {
                $Writer.Dispose()
            }
        } catch {
            # Queue nothing on a partial write — a half-written batch would start a run missing tasks,
            # which looks like success. Drop the file and let the caller see the failure.
            Remove-Item -LiteralPath $BatchPath -Force -ErrorAction SilentlyContinue
            Write-Error "Failed to write batch file for '$OrchestratorName': $($_.Exception.Message)"
            throw
        }

        # The queue claims strictly by priority bucket (P00 first), so this decides who runs
        # when the limiter is saturated. Callers that matter more than the default (baseline
        # runs racing a fleet-wide test sweep) say so on the InputObject; everything else
        # keeps the historical 4.
        $Priority = [int]($InputObject.Priority ?? 4)
        Write-Information "Craft: Queuing orchestrator '$OrchestratorName' ($TaskCount tasks, P$Priority$(if ($PostExecFunctionName) { ", PostExec: $PostExecFunctionName" }))"
        [Craft.Services.OrchestratorBridge]::QueueOrchestrationFromFile(
            $OrchestratorName,
            $BatchPath,
            $Priority,
            $PostExecFunctionName,
            $PostExecParametersJson,
            $InputObject.Reference
        )
        return "Craft-$OrchestratorName"
    }

    $OrchestratorTable = Get-CippTable -TableName 'CippOrchestratorInput'
    $BatchTable = Get-CippTable -TableName 'CippOrchestratorBatch'

    # Ensure orchestrator tables exist
    $null = Get-CippTable -TableName "$($env:WEBSITE_SITE_NAME -replace '-', '')Instances"
    $null = Get-CippTable -TableName "$($env:WEBSITE_SITE_NAME -replace '-', '')History"

    # If already running in processor context (e.g., timer trigger) and we have an InputObject,
    # start orchestration directly without queuing

    $OrchestratorTriggerDisabled = $env:AzureWebJobs_CIPPOrchestrator_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPOrchestrator.Disabled') -in @('true', '1')

    if ($InputObject -and -not $OrchestratorTriggerDisabled) {
        Write-Information 'Running in processor context - starting orchestration directly'
        if ($InputObject.Batch) {
            # Store batch items separately to enable querying and tracking
            $BatchGuid = (New-Guid).Guid.ToString()
            foreach ($BatchItem in $InputObject.Batch) {
                $BatchEntity = @{
                    PartitionKey = $BatchGuid
                    RowKey       = (New-Guid).Guid.ToString()
                    BatchItem    = [string]($BatchItem | ConvertTo-Json -Depth 10 -Compress)
                }
                Add-CIPPAzDataTableEntity @BatchTable -Entity $BatchEntity -Force
            }

            # Remove batch from main input object to reduce size
            $InputObject.PSObject.Properties.Remove('Batch')

            # Add queue function reference to retrieve batch items in orchestrator
            $InputObject | Add-Member -NotePropertyName 'QueueFunction' -NotePropertyValue @{
                FunctionName = 'OrchestratorBatchItems'
                Parameters   = @{
                    BatchId = $BatchGuid
                }
            } -Force
        }
        try {
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
            Write-Information "Orchestration started with instance ID: $InstanceId"
            return $InstanceId
        } catch {
            Write-Error "Failed to start orchestration in processor context: $_"
            throw
        }
    }

    # If we have a GUID, we're being called from the queue trigger - retrieve and execute
    if ($InputObjectGuid) {
        Write-Information "Retrieving orchestrator input object: $InputObjectGuid"
        try {
            $StoredInput = Get-CIPPAzDataTableEntity @OrchestratorTable -Filter "PartitionKey eq 'Input' and RowKey eq '$InputObjectGuid'"

            if (-not $StoredInput) {
                throw "Input object not found for GUID: $InputObjectGuid"
            }

            # Start the orchestration with the compressed JSON string from storage
            # Note: StoredInput.InputObject is already a compressed JSON string
            $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject $StoredInput.InputObject

            Write-Information "Orchestration started with instance ID: $InstanceId"

            # Clean up the stored input object after starting the orchestration
            try {
                $Entities = Get-AzDataTableEntity @OrchestratorTable -Filter "PartitionKey eq 'Input' and (RowKey eq '$InputObjectGuid' or OriginalEntityId eq '$InputObjectGuid' or OriginalEntityId eq guid'$InputObjectGuid')" -Property PartitionKey, RowKey
                Remove-CIPPAzDataTableEntity @OrchestratorTable -Entity $Entities -Force
                Write-Information "Cleaned up stored input object: $InputObjectGuid"
            } catch {
                Write-Warning "Failed to clean up stored input object $InputObjectGuid : $_"
            }

            return $InstanceId

        } catch {
            Write-Error "Failed to start orchestration from stored input: $_"
            throw
        }
    } elseif ($InputObject) {
        try {
            # Store the input object in table storage
            $Guid = (New-Guid).Guid.ToString()

            if ($InputObject.Batch) {
                # Store batch items separately to enable querying and tracking
                foreach ($BatchItem in $InputObject.Batch) {
                    $BatchEntity = @{
                        PartitionKey = $Guid
                        RowKey       = (New-Guid).Guid.ToString()
                        BatchItem    = [string]($BatchItem | ConvertTo-Json -Depth 10 -Compress)
                    }
                    Add-CIPPAzDataTableEntity @BatchTable -Entity $BatchEntity -Force
                }

                # Remove batch from main input object to reduce size
                $InputObject.PSObject.Properties.Remove('Batch')

                # Add queue function reference to retrieve batch items in orchestrator
                $InputObject | Add-Member -MemberType NoteProperty -Force -Name QueueFunction -Value @{
                    FunctionName = 'OrchestratorBatchItems'
                    Parameters   = @{
                        BatchId = $Guid
                    }
                }
            }

            $StoredInput = @{
                PartitionKey = 'Input'
                RowKey       = $Guid
                InputObject  = [string]($InputObject | ConvertTo-Json -Depth 10 -Compress)
            }

            Add-CIPPAzDataTableEntity @OrchestratorTable -Entity $StoredInput -Force
            Write-Information "Stored orchestrator input with GUID: $Guid"

            # Queue the orchestration execution with just the GUID
            Add-CippQueueMessage -Cmdlet 'Start-CIPPOrchestrator' -Parameters @{
                InputObjectGuid = $Guid
            }

            Write-Information "Queued orchestration execution for GUID: $Guid"

        } catch {
            Write-Error "Failed to queue orchestration: $_"
            throw
        }
    } else {
        Write-Warning 'No input object or GUID provided to Start-CIPPOrchestrator. Nothing to execute.'
    }
}
