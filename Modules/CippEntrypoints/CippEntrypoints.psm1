using namespace System.Net

function Receive-CippHttpTrigger {
    Param($Request, $TriggerMetadata)
    #force path to CIPP-API
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName
    Write-Information (Get-Item $PSScriptRoot).Parent.Parent.FullName
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
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName
    $Start = (Get-Date).ToUniversalTime()
    $APIName = $TriggerMetadata.FunctionName
    Write-Information "#### Running $APINAME"
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

    try {
        if (Test-Json -Json $Context.Input) {
            $OrchestratorInput = $Context.Input | ConvertFrom-Json
        } else {
            $OrchestratorInput = $Context.Input
        }
        Write-Information "Orchestrator started $($OrchestratorInput.OrchestratorName)"

        $DurableRetryOptions = @{
            FirstRetryInterval  = (New-TimeSpan -Seconds 5)
            MaxNumberOfAttempts = if ($OrchestratorInput.MaxAttempts) { $OrchestratorInput.MaxAttempts } else { 1 }
            BackoffCoefficient  = 2
        }

        switch ($OrchestratorInput.DurableMode) {
            'FanOut' {
                $DurableMode = 'FanOut'
                $NoWait = $true
            }
            'Sequence' {
                $DurableMode = 'Sequence'
                $NoWait = $false
            }
            default {
                $DurableMode = 'FanOut (Default)'
                $NoWait = $true
            }
        }
        Write-Information "Durable Mode: $DurableMode"

        $RetryOptions = New-DurableRetryOptions @DurableRetryOptions

        if ($Context.IsReplaying -ne $true -and $OrchestratorInput.SkipLog -ne $true) {
            Write-LogMessage -API $OrchestratorInput.OrchestratorName -tenant $OrchestratorInput.TenantFilter -message "Started $($OrchestratorInput.OrchestratorName)" -sev info
        }

        if (!$OrchestratorInput.Batch -or ($OrchestratorInput.Batch | Measure-Object).Count -eq 0) {
            $Batch = (Invoke-ActivityFunction -FunctionName 'CIPPActivityFunction' -Input $OrchestratorInput.QueueFunction -ErrorAction Stop)
        } else {
            $Batch = $OrchestratorInput.Batch
        }

        if (($Batch | Measure-Object).Count -gt 0) {
            $Tasks = foreach ($Item in $Batch) {
                $DurableActivity = @{
                    FunctionName = 'CIPPActivityFunction'
                    Input        = $Item
                    NoWait       = $NoWait
                    RetryOptions = $RetryOptions
                    ErrorAction  = 'Stop'
                }
                Invoke-DurableActivity @DurableActivity
            }
            if ($NoWait) {
                $null = Wait-ActivityFunction -Task $Tasks
            }
        }

        if ($Context.IsReplaying -ne $true -and $OrchestratorInput.SkipLog -ne $true) {
            Write-LogMessage -API $OrchestratorInput.OrchestratorName -tenant $tenant -message "Finished $($OrchestratorInput.OrchestratorName)" -sev Info
        }
    } catch {
        Write-Information "Orchestrator error $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)"
    }
}

function Receive-CippActivityTrigger {
    Param($Item)
    try {
        $Start = (Get-Date).ToUniversalTime()
        Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName

        if ($Item.QueueId) {
            if ($Item.QueueName) {
                $QueueName = $Item.QueueName
            } elseif ($Item.TenantFilter) {
                $QueueName = $Item.TenantFilter
            } elseif ($Item.Tenant) {
                $QueueName = $Item.Tenant
            }
            $QueueTask = @{
                QueueId = $Item.QueueId
                Name    = $QueueName
                Status  = 'Running'
            }
            $TaskStatus = Set-CippQueueTask @QueueTask
            $QueueTask.TaskId = $TaskStatus.RowKey
        }

        if ($Item.FunctionName) {
            $FunctionName = 'Push-{0}' -f $Item.FunctionName
            try {
                & $FunctionName -Item $Item

                if ($TaskStatus) {
                    $QueueTask.Status = 'Completed'
                    $null = Set-CippQueueTask @QueueTask
                }
            } catch {
                $ErrorMsg = $_.Exception.Message
                if ($TaskStatus) {
                    $QueueTask.Status = 'Failed'
                    $null = Set-CippQueueTask @QueueTask
                }
            }
        } else {
            $ErrorMsg = 'Function not provided'
            if ($TaskStatus) {
                $QueueTask.Status = 'Failed'
                $null = Set-CippQueueTask @QueueTask
            }
        }

        $End = (Get-Date).ToUniversalTime()

        try {
            $Stats = @{
                FunctionType = 'Durable'
                Entity       = $Item
                Start        = $Start
                End          = $End
                ErrorMsg     = $ErrorMsg
            }
            Write-CippFunctionStats @Stats
        } catch {
            Write-Information "Error adding activity stats: $($_.Exception.Message)"
        }
    } catch {
        Write-Information "Error in Receive-CippActivityTrigger: $($_.Exception.Message)"
        if ($TaskStatus) {
            $QueueTask.Status = 'Failed'
            $null = Set-CippQueueTask @QueueTask
        }
    }
}

Export-ModuleMember -Function @('Receive-CippHttpTrigger', 'Receive-CippQueueTrigger', 'Receive-CippOrchestrationTrigger', 'Receive-CippActivityTrigger')

