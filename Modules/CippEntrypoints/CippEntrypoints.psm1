using namespace System.Net

function Receive-CippHttpTrigger {
    Param($Request, $TriggerMetadata)
    #force path to CIPP-API
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName
    Write-Host (Get-Item $PSScriptRoot).Parent.Parent.FullName
    $APIName = $TriggerMetadata.FunctionName

    $FunctionName = 'Invoke-{0}' -f $APIName

    $HttpTrigger = @{
        Request         = $Request
        TriggerMetadata = $TriggerMetadata
    }

    & $FunctionName @HttpTrigger
}

function Receive-CippQueueTrigger {
    Param($QueueItem, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName

    $FunctionName = 'Push-{0}' -f $APIName
    $QueueTrigger = @{
        QueueItem       = $QueueItem
        TriggerMetadata = $TriggerMetadata
    }

    & $FunctionName @QueueTrigger
}

Export-ModuleMember -Function @('Receive-CippHttpTrigger', 'Receive-CippQueueTrigger')

