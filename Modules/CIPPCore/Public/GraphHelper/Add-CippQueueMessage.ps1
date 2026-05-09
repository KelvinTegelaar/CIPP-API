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
        [hashtable]$Parameters = @{}
    )

    $QueueMessage = @{
        Cmdlet     = $Cmdlet
        Parameters = $Parameters
    }

    try {
        if ($env:CIPPNG -eq 'true') {
            $ParametersJson = $Parameters | ConvertTo-Json -Depth 10 -Compress
            [Craft.Services.QueueBridge]::Enqueue($Cmdlet, $ParametersJson)
            Write-Information "Craft: Queued $Cmdlet for background execution"
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
