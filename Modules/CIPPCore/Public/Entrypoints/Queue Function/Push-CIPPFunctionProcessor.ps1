function Push-CIPPFunctionProcessor {
    <#
    .SYNOPSIS
    Starts a specified function on the processor node
    #>
    [CmdletBinding()]
    param($QueueItem, $TriggerMetadata)

    Write-Information 'Processor - Received message from queue'

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    $FunctionName = $env:WEBSITE_SITE_NAME
    if ($FunctionName -match '-') {
        $Node = ($FunctionName -split '-')[1]
    } else {
        $Node = 'http'
    }

    if ($env:CIPP_PROCESSOR -ne 'true') {
        return
    }
    if ($Config -and $Config.state -eq $true -and $Node -eq 'proc') {
        return
    }

    $Parameters = $QueueItem.Parameters | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
    if (Get-Command -Name $QueueItem.ProcessorFunction -Module CIPPCore -ErrorAction SilentlyContinue) {
        & $QueueItem.ProcessorFunction @Parameters
    } else {
        Write-Warning "Function $($QueueItem.ProcessorFunction) not found"
    }
}
