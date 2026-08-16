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
            if ("$($Item.Mode)" -eq 'oneoff') {
                # A one-off is an operator pressing Fix and looking at the row - they
                # re-compare within seconds, and the deferred PostExec refresh (run
                # finalization lags a scheduler tick) hands that compare the stale
                # pre-remediation cache: fixed drift re-detects as still broken. One
                # standard means at most a couple of caches, so refresh them inline and
                # return no impact records for PostExec to repeat.
                foreach ($CacheType in @($Result.CacheType | Where-Object { $_ })) {
                    $Collector = "Set-CIPPDBCache$CacheType"
                    try {
                        if (Get-Command -Name $Collector -ErrorAction SilentlyContinue) {
                            $null = & $Collector -TenantFilter $Item.Item.TenantFilter
                        }
                    } catch {
                        Write-Information "Baselines: inline cache refresh $CacheType for $($Item.Item.TenantFilter) failed: $($_.Exception.Message)"
                    }
                }
                return
            }
            # One record per declared cache - the refresh dedupes across standards, so a
            # run that remediates ten Exchange standards still collects each type once.
            foreach ($CacheType in @($Result.CacheType | Where-Object { $_ })) {
                [PSCustomObject]@{
                    TenantFilter = "$($Item.Item.TenantFilter)"
                    CacheType    = "$CacheType"
                }
            }
            return
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
