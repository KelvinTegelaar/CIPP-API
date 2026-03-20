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
    $OrchestratorTable = Get-CippTable -TableName 'CippOrchestratorInput'

    # If already running in processor context (e.g., timer trigger) and we have an InputObject,
    # start orchestration directly without queuing

    $OrchestratorTriggerDisabled = $env:AzureWebJobs_CIPPOrchestrator_Disabled -in @('true', '1') -or [System.Environment]::GetEnvironmentVariable('AzureWebJobs.CIPPOrchestrator.Disabled') -in @('true', '1')

    if ($InputObject -and -not $OrchestratorTriggerDisabled) {
        Write-Information 'Running in processor context - starting orchestration directly'
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
                $Entities = Get-AzDataTableEntity @OrchestratorTable -Filter "PartitionKey eq 'Input' and (RowKey eq '$InputObjectGuid' or OriginalEntityId eq '$InputObjectGuid')" -Property PartitionKey, RowKey
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
