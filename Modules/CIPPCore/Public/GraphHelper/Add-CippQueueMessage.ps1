function Add-CippQueueMessage {
    <#
    .SYNOPSIS
        Push a message to the Azure Storage Queue for background processing
    .DESCRIPTION
        Wraps Push-OutputBinding to send messages to the cippqueue for processing by CippQueueTrigger.
        This offloads orchestration execution to the processor function app.
    .PARAMETER Cmdlet
        The name of the function to execute (must exist in CIPPCore module)
    .PARAMETER Parameters
        Hashtable of parameters to pass to the function
    .PARAMETER Priority
        Queue priority for the starter job (lower = sooner). The queue claims strictly by priority
        bucket, so a starter below the background band (P4) cannot run until that backlog drains.
        Defaults to P2 when called from an HTTP request (user-initiated work skips the queue) and
        P5 otherwise.
    .EXAMPLE
        Add-CippQueueMessage -Cmdlet 'Start-BPAOrchestrator' -Parameters @{ TenantFilter = 'AllTenants'; Force = $true }
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Cmdlet,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 99)]
        [System.Nullable[int]]$Priority
    )

    $QueueMessage = @{
        Cmdlet     = $Cmdlet
        Parameters = $Parameters
    }

    try {
        if ($env:CIPPNG -eq 'true') {
            if ($null -eq $Priority) {
                # Stamped per invocation by the Craft worker; absent on older Craft runtimes.
                $OpContext = $global:CraftOperationContext
                $Priority = if ($null -ne $OpContext -and $OpContext.Category -eq 'HTTP') { 2 } else { 5 }
            }
            $ParametersJson = $Parameters | ConvertTo-Json -Depth 10 -Compress
            try {
                [Craft.Services.QueueBridge]::Enqueue($Cmdlet, $ParametersJson, [int]$Priority)
            } catch [System.Management.Automation.MethodException] {
                # Older Craft runtime without the priority overload - fall back to the default band.
                [Craft.Services.QueueBridge]::Enqueue($Cmdlet, $ParametersJson)
            }
            Write-Information "Craft: Queued $Cmdlet for background execution (P$Priority)"
            return $true
        }

        Push-OutputBinding -Name QueueItem -Value $QueueMessage
        Write-Information "Queued $Cmdlet for execution"
        return $true
    } catch {
        Write-Error "Failed to queue message: $_"
        return $false
    }
}
