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
            Remove-AzDataTableEntity @QueueTable -Entity $QueueItem
            $Parameters = $Queue.Parameters | ConvertFrom-Json -AsHashtable
            if (Get-Command -Name $QueueItem.ProcessorFunction -Module CIPPCore -ErrorAction SilentlyContinue) {
                & $QueueItem.ProcessorFunction @Parameters
            } else {
                Write-Warning "Function $($QueueItem.ProcessorFunction) not found"
            }
        }
    }
}
