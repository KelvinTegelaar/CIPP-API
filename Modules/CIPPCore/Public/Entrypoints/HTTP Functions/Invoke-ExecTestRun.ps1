function Invoke-ExecTestRun {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Tests.ReadWrite
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting data collection and test run for tenant: $TenantFilter" -sev Info
        $Batch = @(
            @{
                FunctionName = 'CIPPDBCacheData'
                TenantFilter = $TenantFilter
                QueueId      = $Queue.RowKey
                QueueName    = "Cache - $TenantFilter"
            }
        )
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'TestDataCollectionAndRun'
            Batch            = $Batch
            PostExecution    = @{
                FunctionName = 'CIPPTestsRun'
                Parameters   = @{
                    TenantFilter = $TenantFilter
                }
            }
            SkipLog          = $false
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)

        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{ Results = "Successfully started data collection and test run for $TenantFilter" }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Data collection and test run orchestration started. Instance ID: $InstanceId" -sev Info

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to start data collection/test run: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Message = "Failed to start data collection/test run for $TenantFilter" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
