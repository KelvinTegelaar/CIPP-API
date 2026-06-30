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
        $Mode = ($Request.Query.mode ?? $Request.Body.mode ?? 'both').ToString().ToLower()
        if ($Mode -notin @('both', 'cache', 'tests')) { $Mode = 'both' }

        switch ($Mode) {
            'tests' {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting tests-only run for tenant: $TenantFilter" -sev Info
                $InstanceId = Start-CIPPDBTestsRun -TenantFilter $TenantFilter -Force
                $ResultMessage = "Successfully started test run for $TenantFilter"
            }
            'cache' {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting cache-only collection for tenant: $TenantFilter" -sev Info
                $Batch = @(
                    @{
                        FunctionName = 'CIPPDBCacheData'
                        TenantFilter = $TenantFilter
                        QueueName    = "Cache - $TenantFilter"
                    }
                )
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = "TestDataCollection-$TenantFilter"
                    Batch            = $Batch
                    SkipLog          = $false
                    PostExecution    = @{
                        FunctionName = 'CIPPDBCacheApplyBatch'
                        Parameters   = @{
                            TenantFilter = $TenantFilter
                        }
                    }
                }
                $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
                $ResultMessage = "Successfully started cache collection for $TenantFilter"
            }
            default {
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting data collection and test run for tenant: $TenantFilter" -sev Info
                $Batch = @(
                    @{
                        FunctionName = 'CIPPDBCacheData'
                        TenantFilter = $TenantFilter
                        QueueName    = "Cache - $TenantFilter"
                    }
                )
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = "TestDataCollectionAndRun-$TenantFilter"
                    Batch            = $Batch
                    SkipLog          = $false
                    PostExecution    = @{
                        FunctionName = 'CIPPDBCacheApplyBatch'
                        Parameters   = @{
                            TestRun      = $true
                            TenantFilter = $TenantFilter
                        }
                    }
                }
                $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
                $ResultMessage = "Successfully started data collection and test run for $TenantFilter"
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{ Results = $ResultMessage }
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
