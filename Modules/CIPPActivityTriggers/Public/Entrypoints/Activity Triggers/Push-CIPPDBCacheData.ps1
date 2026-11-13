function Push-CIPPDBCacheData {
    <#
    .SYNOPSIS
        List cache collection tasks for a single tenant (Phase 1 of fan-out/fan-in)

    .DESCRIPTION
        Checks tenant license capabilities and returns a list of grouped cache collection work items.
        Each item represents one collection type (Graph, ExchangeConfig, ExchangeData, etc.) that
        will run all its cache functions sequentially within a single activity invocation.

        This grouped approach reduces activity count from ~50-67 per tenant down to ~2-6 per tenant,
        dramatically cutting orchestrator replay overhead and table storage I/O.

        Does NOT start sub-orchestrators. The returned items are aggregated by the PostExecution
        function (CIPPDBCacheApplyBatch) and executed in a single flat orchestrator.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    Write-Host "Building cache task list for tenant: $($Item.TenantFilter)"
    $TenantFilter = $Item.TenantFilter
    $QueueId = $Item.QueueId

    try {
        $Licensed = @{}
        $Tasks = foreach ($Entry in (Get-CIPPDBCacheSchedule).GetEnumerator()) {
            $License = $Entry.Value.License
            if ($License) {
                if (-not $Licensed.ContainsKey($License)) {
                    $Licensed[$License] = Test-CIPPStandardLicense -StandardName "$($License)LicenseCheck" -TenantFilter $TenantFilter -Preset $License -SkipLog
                }
                if (-not $Licensed[$License]) {
                    Write-Host "Skipping $($Entry.Key) data collection for $TenantFilter - no $License license"
                    continue
                }
            }
            $Task = @{
                FunctionName = 'ExecCIPPDBCache'
                TenantFilter = $TenantFilter
                QueueId      = $QueueId
                QueueName    = "DB Cache $($Entry.Key) - $TenantFilter"
            }
            if ($Entry.Value.Types) { $Task.CollectionType = $Entry.Key } else { $Task.Name = $Entry.Key }
            $Task
        }

        Write-Information "Built $(@($Tasks).Count) grouped cache tasks for tenant $TenantFilter"

        # Return the task list — the PostExecution function will aggregate and start a flat orchestrator
        return @($Tasks)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to build cache task list: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @()
    }
}
