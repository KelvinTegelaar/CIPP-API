function Push-Z_CIPPQueueTrigger {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    Param($QueueItem, $TriggerMetadata)
    $APIName = $QueueItem.FunctionName

    $FunctionName = 'Push-{0}' -f $APIName
    if (Get-Command -Name $FunctionName -ErrorAction SilentlyContinue) {
        & $FunctionName -QueueItem $QueueItem -TriggerMetadata $TriggerMetadata
    }
}