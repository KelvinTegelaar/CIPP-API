using namespace System.Net

function Receive-CippHttpTrigger {
    <#
    .SYNOPSIS
        Execute HTTP trigger function
    .DESCRIPTION
        Execute HTTP trigger function from an azure function app
    .PARAMETER Request
        The request object from the function app
    .PARAMETER TriggerMetadata
        The trigger metadata object from the function app
    .FUNCTIONALITY
        Entrypoint
    #>
    param(
        $Request,
        $TriggerMetadata
    )

    if ($Request.Headers.'x-ms-coldstart' -eq 1) {
        Write-Information '** Function app cold start detected **'
    }

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -eq 'true') {
            Write-Information 'No API Calls'
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = 'API calls are not accepted on this function app'
                })
            return
        }
    }

    # Convert the request to a PSCustomObject because the httpContext is case sensitive since 7.3
    $Request = $Request | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    Set-Location (Get-Item $PSScriptRoot).Parent.Parent.FullName
    $FunctionName = 'Invoke-{0}' -f $Request.Params.CIPPEndpoint
    Write-Information "Function: $($Request.Params.CIPPEndpoint)"

    $HttpTrigger = @{
        Request         = [pscustomobject]($Request)
        TriggerMetadata = $TriggerMetadata
    }

    if ((Get-Command -Name $FunctionName -ErrorAction SilentlyContinue) -or $FunctionName -eq 'Invoke-Me') {
        try {
            $Access = Test-CIPPAccess -Request $Request
            if ($FunctionName -eq 'Invoke-Me') {
                return
            }
        } catch {
            Write-Information "Access denied for $FunctionName : $($_.Exception.Message)"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = $_.Exception.Message
                })
            return
        }
        
        try {
            Write-Information "Access: $Access"
            if ($Access) {
                & $FunctionName @HttpTrigger
            }
        } catch {
            Write-Warning "Exception occurred on HTTP trigger ($FunctionName): $($_.Exception.Message)"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = $_.Exception.Message
                })
        }
    } else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::NotFound
                Body       = 'Endpoint not found'
            })
    }
    return
}

function Receive-CippOrchestrationTrigger {
    <#
    .SYNOPSIS
        Execute durable orchestrator function
    .DESCRIPTION
        Execute orchestrator from azure function app
    .PARAMETER Context
        The context object from the function app
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Context)

    try {
        if (Test-Json -Json $Context.Input) {
            $OrchestratorInput = $Context.Input | ConvertFrom-Json
        } else {
            $OrchestratorInput = $Context.Input
        }
        Write-Information "Orchestrator started $($OrchestratorInput.OrchestratorName)"
        Write-Warning "Receive-CippOrchestrationTrigger - $($OrchestratorInput.OrchestratorName)"
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
            Write-Information "Batch Count: $($Batch.Count)"
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
            if ($NoWait -and $Tasks) {
                $null = Wait-ActivityFunction -Task $Tasks
            }
        }

        if ($Context.IsReplaying -ne $true -and $OrchestratorInput.SkipLog -ne $true) {
            Write-LogMessage -API $OrchestratorInput.OrchestratorName -tenant $tenant -message "Finished $($OrchestratorInput.OrchestratorName)" -sev Info
        }
    } catch {
        Write-Information "Orchestrator error $($_.Exception.Message) line $($_.InvocationInfo.ScriptLineNumber)"
    }
    return $true
}

function Receive-CippActivityTrigger {
    <#
    .SYNOPSIS
        Execute durable activity function
    .DESCRIPTION
        Execute durable activity function from an orchestrator
    .PARAMETER Item
        The item to process
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)
    Write-Warning "Hey Boo, the activity function is running. Here's some info: $($Item | ConvertTo-Json -Depth 10 -Compress)"
    try {
        $Start = Get-Date
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
                Write-Warning "Activity starting Function: $FunctionName."
                Invoke-Command -ScriptBlock { & $FunctionName -Item $Item }
                Write-Warning "Activity completed Function: $FunctionName."
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

        $End = Get-Date

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
    return $true
}

function Receive-CIPPTimerTrigger {
    <#
    .SYNOPSIS
        This function is used to execute timer functions based on the cron schedule.
    .DESCRIPTION
        This function is used to execute timer functions based on the cron schedule.
    .PARAMETER Timer
        The timer trigger object from the function app
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Timer)

    $UtcNow = (Get-Date).ToUniversalTime()
    $Functions = Get-CIPPTimerFunctions
    $Table = Get-CIPPTable -tablename CIPPTimers
    $Statuses = Get-CIPPAzDataTableEntity @Table
    $FunctionName = $env:WEBSITE_SITE_NAME

    foreach ($Function in $Functions) {
        Write-Information "CIPPTimer: $($Function.Command) - $($Function.Cron)"
        $FunctionStatus = $Statuses | Where-Object { $_.RowKey -eq $Function.Id }
        if ($FunctionStatus.OrchestratorId) {
            $FunctionName = $env:WEBSITE_SITE_NAME
            $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f ($FunctionName -replace '-', ''))
            $Instance = Get-CIPPAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$($FunctionStatus.OrchestratorId)'" -Property PartitionKey, RowKey, RuntimeStatus
            if ($Instance.RuntimeStatus -eq 'Running') {
                Write-LogMessage -API 'TimerFunction' -message "$($Function.Command) - $($FunctionStatus.OrchestratorId) is still running" -sev Warn -LogData $FunctionStatus
                Write-Warning "CIPP Timer: $($Function.Command) - $($FunctionStatus.OrchestratorId) is still running, skipping execution"
                continue
            }
        }
        try {
            if ($FunctionStatus.PSObject.Properties.Name -contains 'ErrorMsg') {
                $FunctionStatus.ErrorMsg = ''
            }

            $Parameters = @{}
            if ($Function.Parameters) {
                $Parameters = $Function.Parameters | ConvertTo-Json | ConvertFrom-Json -AsHashtable
            }

            $Results = Invoke-Command -ScriptBlock { & $Function.Command @Parameters }
            if ($Results -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                $FunctionStatus.OrchestratorId = $Results
                $Status = 'Started'
            } else {
                $Status = 'Completed'
            }
        } catch {
            $Status = 'Failed'
            $ErrorMsg = $_.Exception.Message
            if ($FunctionStatus.PSObject.Properties.Name -contains 'ErrorMsg') {
                $FunctionStatus.ErrorMsg = $ErrorMsg
            } else {
                $FunctionStatus | Add-Member -MemberType NoteProperty -Name ErrorMsg -Value $ErrorMsg
            }
            Write-Information "Error in CIPPTimer for $($Function.Command): $($_.Exception.Message)"
        }
        $FunctionStatus.LastOccurrence = $UtcNow
        $FunctionStatus.Status = $Status

        Add-CIPPAzDataTableEntity @Table -Entity $FunctionStatus -Force
    }
    return $true
}

Export-ModuleMember -Function @('Receive-CippHttpTrigger', 'Receive-CippOrchestrationTrigger', 'Receive-CippActivityTrigger', 'Receive-CIPPTimerTrigger')

