function Push-CIPPBaselineStandard {
    <#
    .SYNOPSIS
        Durable activity: run one baseline standard against one tenant.
    .DESCRIPTION
        Returns an impact record ({ TenantFilter, CacheType }) when the run actually
        remediated, so the PostExecution step (Push-CIPPBaselineCacheRefresh) can refresh
        exactly the caches that were written to - and nothing else.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    try {
        # Stamp every log line this invocation writes with the run's BaselineRunId column,
        # so ListLogs can filter to one exact run.
        Set-CippBaselineRunContext -RunId $Item.RunId
        $Result = Invoke-CIPPBaselineStandard -Item $Item.Item -Mode ($Item.Mode ?? 'run') -TriggeredBy ($Item.TriggeredBy ?? 'schedule') -Force:([bool]$Item.Force) -RunId $Item.RunId
        if ($Result.Remediated -and $Result.CacheType) {
            return [PSCustomObject]@{
                TenantFilter = "$($Item.Item.TenantFilter)"
                CacheType    = "$($Result.CacheType)"
            }
        }
    } catch {
        Write-LogMessage -API 'Baselines' -tenant $Item.Item.TenantFilter -message "Baseline activity failed for $($Item.Item.Standard): $($_.Exception.Message)" -Sev 'Error'
    } finally {
        Set-CippBaselineRunContext -RunId $null
        if ($Item.QueueId) {
            $null = Update-CippQueueEntry -RowKey $Item.QueueId -Status 'Running' -Name $Item.QueueName
        }
    }
}
