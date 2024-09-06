function Push-CIPPFunctionProcessor {
    <#
    .SYNOPSIS
    Starts a specified function on the processor node
    #>
    [CmdletBinding()]
    param($QueueItem)

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            return
        }
    }

    $Parameters = $QueueItem.Parameters | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

    if (Get-Command -Name $QueueItem.FunctionName -Module CIPPCore -ErrorAction SilentlyContinue) {
        & $QueueItem.ProcessorFunction @Parameters
    } else {
        Write-Warning "Function $($QueueItem.FunctionName) not found"
    }
}
