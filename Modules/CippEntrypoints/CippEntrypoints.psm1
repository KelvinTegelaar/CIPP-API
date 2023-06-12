using namespace System.Net

function Receive-CippHttpTrigger {
    Param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    $FunctionVerbs = @{
        'Get'    = '^(:?Ext)?(?<APIName>List.+$)'
        'Update' = '^(:?Ext)?(?<APIName>Edit.+$)'
        'New'    = '^(:?Ext)?(?<APIName>Add.+$)'
        'Invoke' = '^(?<APIName>Exec.+$)'
    }

    $PermissionActions = @{
        'List' = 'readonly'
        'Edit' = 'editor'
        'Add'  = 'editor'
        'Exec' = 'admin'
    }

    foreach ($FunctionVerb in $FunctionVerbs.Keys) {
        if ($APIName -match $FunctionVerbs.$FunctionVerb) {
            $FunctionName = '{0}-{1}' -f $FunctionVerb, $Matches.APIName
            $ApiFunction = $Matches.APIName

            foreach ($Action in $PermissionActions.Keys) {
                if ($ApiFunction -match "^$Action") {
                    $ApiPermission = $PermissionActions.$Action
                    break
                }
            }
            break
        }
    }

    if ($APIName -match '^Ext') {
        $AccessResult = Confirm-CippApiAccess -Request $Request -AccessLevel $ApiPermission
        if (!$AccessResult.Authorized) { return }
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

