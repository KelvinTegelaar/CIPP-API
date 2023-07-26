using namespace System.Net

function Receive-CippHttpTrigger {
    Param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    $FunctionVerbs = @{
        'Get'    = '^(?<APIName>List.+$)'
        'Update' = '^(?<APIName>Edit.+$)'
        'New'    = '^(?<APIName>Add.+$)'
        'Invoke' = '^(?<APIName>Exec.+$)'
    }

    foreach ($FunctionVerb in $FunctionVerbs.Keys) {
        if ($APIName -match $FunctionVerbs.$FunctionVerb) {
            $FunctionName = '{0}-{1}' -f $FunctionVerb, $Matches.APIName
            break
        }
    }

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

