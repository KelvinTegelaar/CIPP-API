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

    $Start = (Get-Date).ToUniversalTime()
    $APIName = $TriggerMetadata.FunctionName
    Write-Host "#### Running $APINAME"
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName
    $FunctionName = 'Push-{0}' -f $APIName
    $QueueTrigger = @{
        QueueItem       = $QueueItem
        TriggerMetadata = $TriggerMetadata
    }
    try {
        & $FunctionName @QueueTrigger
    } catch {
        $ErrorMsg = $_.Exception.Message
    }

    $End = (Get-Date).ToUniversalTime()

    $Stats = @{
        FunctionType = 'Queue'
        Entity       = $QueueItem
        Start        = $Start
        End          = $End
        ErrorMsg     = $ErrorMsg
    }
    Write-Information '####### Adding stats'
    Write-CippFunctionStats @Stats
}

function Receive-CippOrchestrationTrigger {
    param($Context)

    $DurableRetryOptions = @{
        FirstRetryInterval  = (New-TimeSpan -Seconds 5)
        MaxNumberOfAttempts = 3
        BackoffCoefficient  = 2
    }
    $RetryOptions = New-DurableRetryOptions @DurableRetryOptions
    Write-LogMessage -API $Context.Input.OrchestratorName -tenant $Context.Input.TenantFilter -message "Started $($Context.Input.OrchestratorName)" -sev info

    if (!$Context.Input.Batch -or ($Context.Input.Batch | Measure-Object).Count -eq 0) {
        $Batch = (Invoke-ActivityFunction -FunctionName 'CIPPActivityFunction' -Input $Context.Input.QueueFunction)
    } else {
        $Batch = $Context.Input.Batch
    }

    foreach ($Item in $Batch) {
        Invoke-DurableActivity -FunctionName 'CIPPActivityFunction' -Input $Item -NoWait -RetryOptions $RetryOptions
    }

    Write-LogMessage -API $Context.Input.OrchestratorName -tenant $tenant -message "Finished $($Context.Input.OrchestratorName)" -sev Info
}

function Receive-CippActivityTrigger {
    Param($Item)

    $Start = (Get-Date).ToUniversalTime()
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName

    if ($Item.FunctionName) {
        $FunctionName = 'Push-{0}' -f $Item.FunctionName
        try {
            & $FunctionName @Item
        } catch {
            $ErrorMsg = $_.Exception.Message
        }
    } else {
        $ErrorMsg = 'Function not provided'
    }

    $End = (Get-Date).ToUniversalTime()

    $Stats = @{
        FunctionType = 'Durable'
        Entity       = $Item
        Start        = $Start
        End          = $End
        ErrorMsg     = $ErrorMsg
    }
    Write-Information '####### Adding stats'
    Write-CippFunctionStats @Stats
}

Export-ModuleMember -Function @('Receive-CippHttpTrigger', 'Receive-CippQueueTrigger', 'Receive-CippOrchestrationTrigger', 'Receive-CippActivityTrigger')

