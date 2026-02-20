function Start-CIPPProcessorQueue {
    <#
    .SYNOPSIS
    Starts a specified function on the processor node
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $QueueTable = Get-CIPPTable -tablename 'ProcessorQueue'
    $QueueItems = Get-CIPPAzDataTableEntity @QueueTable -Filter "PartitionKey eq 'Function'"

    foreach ($QueueItem in $QueueItems) {
        $FunctionName = $QueueItem.FunctionName ?? $QueueItem.RowKey
        if ($PSCmdlet.ShouldProcess("Processing function $($FunctionName)")) {
            Write-Information "Running queued function $($FunctionName)"
            if ($QueueItem.Parameters) {
                try {
                    $Parameters = $QueueItem.Parameters | ConvertFrom-Json -AsHashtable
                } catch {
                    $Parameters = @{}
                }
            } else {
                $Parameters = @{}
            }
            if (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue) {
                try {
                    # Prepare telemetry metadata
                    $metadata = @{
                        FunctionName = $FunctionName
                        TriggerType  = 'ProcessorQueue'
                        QueueRowKey  = $QueueItem.RowKey
                    }

                    # Add parameters info if available
                    if ($Parameters.Count -gt 0) {
                        $metadata['ParameterCount'] = $Parameters.Count
                        # Add common parameters
                        if ($Parameters.Tenant) {
                            $metadata['Tenant'] = $Parameters.Tenant
                        }
                        if ($Parameters.TenantFilter) {
                            $metadata['Tenant'] = $Parameters.TenantFilter
                        }
                    }

                    # Wrap function execution with telemetry

                    Invoke-Command -ScriptBlock { & $FunctionName @Parameters }

                } catch {
                    Write-Warning "Failed to run function $($FunctionName). Error: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "Function $($FunctionName) not found"
            }
            Remove-AzDataTableEntity -Force @QueueTable -Entity $QueueItem
        }
    }
}
