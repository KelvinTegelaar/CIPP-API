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
        if ($PSCmdlet.ShouldProcess("Processing function $($QueueItem.FunctionName)")) {
            Write-Information "Running queued function $($QueueItem.FunctionName)"
            if ($QueueItem.Parameters) {
                try {
                    $Parameters = $QueueItem.Parameters | ConvertFrom-Json -AsHashtable
                } catch {
                    $Parameters = @{}
                }
            } else {
                $Parameters = @{}
            }
            if (Get-Command -Name $QueueItem.FunctionName -ErrorAction SilentlyContinue) {
                try {
                    Invoke-Command -ScriptBlock { & $QueueItem.FunctionName @Parameters }
                } catch {
                    Write-Warning "Failed to run function $($QueueItem.FunctionName). Error: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "Function $($QueueItem.FunctionName) not found"
            }
            Remove-AzDataTableEntity -Force @QueueTable -Entity $QueueItem
        }
    }
}
