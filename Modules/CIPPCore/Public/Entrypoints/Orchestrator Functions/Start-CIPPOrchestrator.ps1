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

    # ─── CIPPNG runtime: push batch directly to OrchestratorService ───
    if ($env:CIPPNG -eq 'true' -and $InputObject) {
        $OrchestratorName = $InputObject.OrchestratorName ?? 'UnnamedOrchestrator'

        # QueueFunction pattern: call the function first to generate batch items
        if (-not $InputObject.Batch -and $InputObject.QueueFunction) {
            $QueueFuncName = "Push-$($InputObject.QueueFunction.FunctionName)"
            Write-Information "CIPP-NG: Calling QueueFunction '$QueueFuncName' to build batch for '$OrchestratorName'"
            $QueueItem = [PSCustomObject]@{}
            if ($InputObject.QueueFunction.Parameters) {
                $QueueItem = [PSCustomObject]$InputObject.QueueFunction.Parameters
            }
            $BatchResult = & $QueueFuncName -Item $QueueItem
            $QueueBatch = @($BatchResult | Where-Object { $null -ne $_ })
            if ($QueueBatch.Count -eq 0) {
                Write-Information "CIPP-NG: QueueFunction '$QueueFuncName' returned 0 tasks for '$OrchestratorName' - skipping"
                return "CIPPNG-$OrchestratorName-NoTasks"
            }
            $InputObject | Add-Member -MemberType NoteProperty -Name 'Batch' -Value $QueueBatch -Force
        }

        $BatchJson = ConvertTo-Json -InputObject @($InputObject.Batch) -Depth 10 -Compress

        $PostExecFunctionName = $null
        $PostExecParametersJson = $null
        if ($InputObject.PostExecution) {
            $PostExecFunctionName = $InputObject.PostExecution.FunctionName
            if ($InputObject.PostExecution.Parameters) {
                $PostExecParametersJson = $InputObject.PostExecution.Parameters | ConvertTo-Json -Depth 10 -Compress
            }
        }

        Write-Information "CIPP-NG: Queuing orchestrator '$OrchestratorName' ($($InputObject.Batch.Count) tasks$(if ($PostExecFunctionName) { ", PostExec: $PostExecFunctionName" }))"
        [CIPPASP.Services.OrchestratorBridge]::QueueOrchestration(
            $OrchestratorName,
            $BatchJson,
            4,
            $PostExecFunctionName,
            $PostExecParametersJson
        )
        return "CIPPNG-$OrchestratorName"
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
                Remove-AzDataTableEntity @OrchestratorTable -Entity $Entities -Force
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
