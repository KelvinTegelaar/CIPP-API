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
                $RefreshCaches = {
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
                }
                & $RefreshCaches
                # Lag-prone Graph surfaces (organization, admin/sharepoint/settings) can
                # hand that refresh PRE-write state, and a present-but-stale cache never
                # re-collects - collection only fires on a miss, so the fixed drift would
                # re-detect until the next scheduled collection. Verify the refreshed
                # cache actually grades clean; if not, give propagation a moment and
                # collect ONCE more. Still drifted after that is worth a warning, not a
                # loop: either the write truly failed or the API lags beyond reason, and
                # the scheduled collection remains the backstop.
                try {
                    $Verify = @{ Item = $Item.Item; Mode = 'oneoff'; TriggeredBy = ($Item.TriggeredBy ?? 'schedule'); RunId = $Item.RunId }
                    $Verdict = Invoke-CIPPBaselineStandard @Verify -GradeOnly
                    if ($Verdict -and -not $Verdict.Compliant) {
                        Start-Sleep -Seconds 10
                        & $RefreshCaches
                        $Verdict = Invoke-CIPPBaselineStandard @Verify -GradeOnly
                        if ($Verdict -and -not $Verdict.Compliant) {
                            Write-LogMessage -API 'Baselines' -tenant $Item.Item.TenantFilter -message "The refreshed cache still grades `"$($Item.Item.Standard)`" as drifted after remediation - either the write did not take effect or the API is lagging beyond the retry window; the next compare may re-report drift until the scheduled collection." -Sev 'Warning'
                        }
                    }
                } catch {
                    Write-Information "Baselines: post-remediation cache verification for $($Item.Item.Standard) failed: $($_.Exception.Message)"
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
