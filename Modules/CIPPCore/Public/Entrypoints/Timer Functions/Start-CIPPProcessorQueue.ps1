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
            if (Get-Command -Name $QueueItem.FunctionName -Module CIPPCore -ErrorAction SilentlyContinue) {
                & $QueueItem.FunctionName @Parameters
            } else {
                Write-Warning "Function $($QueueItem.FunctionName) not found"
            }
            Remove-AzDataTableEntity @QueueTable -Entity $QueueItem
        }
    }
}
