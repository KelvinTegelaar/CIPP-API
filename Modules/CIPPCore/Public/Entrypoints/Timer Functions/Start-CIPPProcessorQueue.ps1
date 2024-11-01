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
        if ($PSCmdlet.ShouldProcess("Processing function $($QueueItem.ProcessorFunction)")) {
            Write-Information "Running queued function $($QueueItem.ProcessorFunction)"
            if ($QueueItem.Parameters) {
                try {
                    $Parameters = $QueueItem.Parameters | ConvertFrom-Json -AsHashtable
                } catch {
                    $Parameters = @{}
                }
            } else {
                $Parameters = @{}
            }
            if (Get-Command -Name $QueueItem.ProcessorFunction -Module CIPPCore -ErrorAction SilentlyContinue) {
                try {
                    Invoke-Command -ScriptBlock { & $QueueItem.ProcessorFunction @Parameters }
                } catch {
                    Write-Warning "Failed to run function $($QueueItem.ProcessorFunction). Error: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "Function $($QueueItem.ProcessorFunction) not found"
            }
            Remove-AzDataTableEntity @QueueTable -Entity $QueueItem
        }
    }
}
