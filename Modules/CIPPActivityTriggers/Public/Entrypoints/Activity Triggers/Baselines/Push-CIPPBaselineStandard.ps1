function Push-CIPPBaselineStandard {
    <#
    .SYNOPSIS
        Durable activity: run one baseline standard against one tenant.
    .DESCRIPTION
        Returns an impact record ({ TenantFilter, CacheType, Standard }) when the run actually
        remediated, in every mode, so the PostExecution step (Push-CIPPBaselineCacheRefresh)
        refreshes each written cache once per tenant and then verifies the fixed standards.
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
            # One record per declared cache - the refresh dedupes across standards, so a
            # run that remediates ten Exchange standards still collects each type once.
            foreach ($CacheType in @($Result.CacheType | Where-Object { $_ })) {
                [PSCustomObject]@{
                    TenantFilter = "$($Item.Item.TenantFilter)"
                    CacheType    = "$CacheType"
                    Standard     = "$($Item.Item.Standard)"
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
