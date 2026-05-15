function Invoke-ListWorkerHealth {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Action = $Request.Query.Action ?? 'Snapshot'

    try {
        switch ($Action) {
            'Snapshot' {
                $Snapshot = [Craft.Services.WorkerMetricsBridge]::GetSnapshot()
                $Body = @{ Results = $Snapshot }
            }
            'Summary' {
                $Summary = [Craft.Services.WorkerMetricsBridge]::GetSummary()
                $Body = @{ Results = $Summary }
            }
            'Pool' {
                $PoolType = $Request.Query.PoolType ?? 'http'
                $Pool = [Craft.Services.WorkerMetricsBridge]::GetPoolMetrics($PoolType)
                $Body = @{ Results = $Pool }
            }
            'Jobs' {
                $RunName = $Request.Query.RunName
                $Status = $Request.Query.Status
                $Limit = if ($Request.Query.Limit) { [int]$Request.Query.Limit } else { 100 }
                $Jobs = [Craft.Services.WorkerMetricsBridge]::GetJobDetails($RunName, $Status, $Limit)
                $Body = @{ Results = $Jobs }
            }
            'Runs' {
                $Runs = [Craft.Services.WorkerMetricsBridge]::GetRunSummaries()
                $Body = @{ Results = $Runs }
            }
            'CancelJob' {
                $JobId = $Request.Query.JobId ?? $Request.Body.JobId
                if (-not $JobId) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = 'JobId is required' }
                    }
                }
                $Result = [Craft.Services.WorkerMetricsBridge]::CancelJob($JobId)
                $Body = @{ Results = @{ Success = $Result; JobId = $JobId } }
            }
            'CancelRun' {
                $RunName = $Request.Query.RunName ?? $Request.Body.RunName
                if (-not $RunName) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = 'RunName is required' }
                    }
                }
                $Cancelled = [Craft.Services.WorkerMetricsBridge]::CancelRun($RunName)
                $Body = @{ Results = @{ Success = $true; RunName = $RunName; CancelledCount = $Cancelled } }
            }
            'DeleteJob' {
                $JobId = $Request.Query.JobId ?? $Request.Body.JobId
                if (-not $JobId) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = 'JobId is required' }
                    }
                }
                $Result = [Craft.Services.WorkerMetricsBridge]::DeleteJob($JobId)
                $Body = @{ Results = @{ Success = $Result; JobId = $JobId } }
            }
            'PurgeCompleted' {
                $Purged = [Craft.Services.WorkerMetricsBridge]::PurgeCompleted()
                $Body = @{ Results = @{ Success = $true; PurgedCount = $Purged } }
            }
            'ChangePriority' {
                $JobId = $Request.Query.JobId ?? $Request.Body.JobId
                $NewPriority = $Request.Query.Priority ?? $Request.Body.Priority
                if (-not $JobId -or $null -eq $NewPriority) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = 'JobId and Priority are required' }
                    }
                }
                $Result = [Craft.Services.WorkerMetricsBridge]::ChangePriority($JobId, [int]$NewPriority)
                $Body = @{ Results = @{ Success = $Result; JobId = $JobId; NewPriority = [int]$NewPriority } }
            }
            default {
                $Body = @{ Results = "Unknown action: $Action" }
                return [HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = $Body
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Worker health error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
        }
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
