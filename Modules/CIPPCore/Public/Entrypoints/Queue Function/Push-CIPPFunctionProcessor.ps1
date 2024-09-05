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
        if ($env:CIPP_PROCESSOR -ne 'true' -and !$All.IsPresent) {
            return
        }
    }

    if (Get-Command -Name $QueueItem.FunctionName -Module CIPPCore -ErrorAction SilentlyContinue) {
        & $QueueItem.FunctionName
    } else {
        Write-Warning "Function $($QueueItem.FunctionName) not found"
    }
}
