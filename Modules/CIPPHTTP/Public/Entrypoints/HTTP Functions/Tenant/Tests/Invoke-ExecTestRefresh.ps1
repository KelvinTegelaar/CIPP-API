function Invoke-ExecTestRefresh {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Tests.ReadWrite
    .DESCRIPTION
        Queues one or more tests for a tenant on the background workers and returns the QueueId to poll with ListCippQueue. Fresh results are in ListTests once the queue completes.
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # A test id (e.g. SecuritySimulation_MfaTampering), or an array of them to queue as one run.
    $TestNames = @($Request.Query.testName ?? $Request.Body.testName | Where-Object { $_ })

    if ($TestNames.Count -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Message = "Failed to queue test refresh for $TenantFilter"; Error = 'testName is required' }
            })
    }

    try {
        $Unknown = @(foreach ($TestName in $TestNames) {
                if ((Resolve-CIPPCommand -Name "Invoke-CippTest$TestName").ModuleName -ne 'CIPPTests') { $TestName }
            })
        if ($Unknown.Count -gt 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Message = "Test function not found: $($Unknown -join ', ')" }
                })
        }

        $Queue = New-CippQueueEntry -Name "Test refresh ($TenantFilter)" -TotalTasks $TestNames.Count
        $Batch = foreach ($TestName in $TestNames) {
            [PSCustomObject]@{
                FunctionName = 'CIPPTest'
                TenantFilter = $TenantFilter
                TestId       = $TestName
                QueueId      = $Queue.RowKey
                QueueName    = "$TestName ($TenantFilter)"
            }
        }
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                OrchestratorName = "TestRefresh_$TenantFilter"
                Batch            = @($Batch)
                SkipLog          = $true
            })

        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{
            Results  = "Queued $($TestNames.Count) test(s) for $TenantFilter"
            Metadata = @{ QueueId = $Queue.RowKey }
        }
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Queued test refresh for $($TestNames -join ', ')" -Sev 'Info'
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to queue test refresh for ${TenantFilter}: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{
            Message = "Failed to queue test refresh for $TenantFilter"
            Error   = $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
