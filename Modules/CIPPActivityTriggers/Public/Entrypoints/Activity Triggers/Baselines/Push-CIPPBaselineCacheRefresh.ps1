function Push-CIPPBaselineCacheRefresh {
    <#
    .SYNOPSIS
        PostExecution for baseline runs: refresh only the caches remediations touched.
    .DESCRIPTION
        Runs once after every check in a baseline run has finished. Receives all
        Push-CIPPBaselineStandard return values, keeps the (tenant, cacheType) pairs where a
        remediation actually wrote, dedupes them (many standards share a cacheType), and
        starts one flat orchestrator reusing the existing per-type cache collection activity.
        Nothing remediated = no cache work at all - and without this, the next run would
        re-read the stale pre-remediation cache and re-detect drift that is already fixed.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    try {
        Set-CippBaselineRunContext -RunId $Item.Parameters.RunId
        $Impacted = @{}
        foreach ($ActivityResult in @($Item.Results)) {
            foreach ($Record in @($ActivityResult)) {
                if ($Record -and $Record.CacheType -and $Record.TenantFilter) {
                    $Impacted[('{0}|{1}' -f $Record.TenantFilter, $Record.CacheType)] = $Record
                }
            }
        }
        if ($Impacted.Count -eq 0) {
            Write-Information 'Baseline cache refresh: nothing was remediated - no caches to refresh.'
            return
        }

        $Queue = New-CippQueueEntry -Name "Baseline cache refresh ($($Impacted.Count) caches)" -TotalTasks $Impacted.Count
        $Batch = foreach ($Record in $Impacted.Values) {
            [PSCustomObject]@{
                FunctionName = 'ExecCIPPDBCache'
                Name         = "$($Record.CacheType)"
                TenantFilter = "$($Record.TenantFilter)"
                QueueName    = ('{0} Cache - {1}' -f $Record.CacheType, $Record.TenantFilter)
                QueueId      = $Queue.RowKey
            }
        }
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = 'BaselineCacheRefresh'
                SkipLog          = $true
            })
        Write-LogMessage -API 'Baselines' -message "Baseline run finished - refreshing $($Impacted.Count) impacted cache(s)." -Sev 'Info'
    } catch {
        Write-LogMessage -API 'Baselines' -message "Baseline cache refresh failed: $($_.Exception.Message)" -Sev 'Error'
    }
}
