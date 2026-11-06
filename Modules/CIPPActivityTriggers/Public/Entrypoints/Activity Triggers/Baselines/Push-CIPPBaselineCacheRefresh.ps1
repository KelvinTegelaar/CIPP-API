function Push-CIPPBaselineCacheRefresh {
    <#
    .SYNOPSIS
        PostExecution for baseline runs: refresh only the caches remediations touched.
    .DESCRIPTION
        Runs once after every check in a baseline run has finished. Records today's fleet
        trend rollup, then receives all Push-CIPPBaselineStandard return values, keeps the
        (tenant, cacheType) pairs where a remediation actually wrote, dedupes them (many
        standards share a cacheType), and starts one flat orchestrator reusing the existing
        per-type cache collection activity. Nothing remediated = no cache work at all - and
        without this, the next run would re-read the stale pre-remediation cache and
        re-detect drift that is already fixed.
        That refresh's own PostExecution calls back here with Parameters.Verify (each tenant's
        remediated standards) and starts one compare run per tenant against the fresh cache,
        which replaces each optimistic Compliant + PendingVerification row with the verified
        verdict.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    try {
        Set-CippBaselineRunContext -RunId $Item.Parameters.RunId

        if ($Item.Parameters.Verify) {
            foreach ($Entry in @($Item.Parameters.Verify)) {
                try {
                    $null = Start-CIPPBaselineOrchestrator -TenantFilter $Entry.TenantFilter -StandardName @($Entry.Standards) -Mode 'compare' -TriggeredBy 'verification'
                } catch {
                    Write-LogMessage -API 'Baselines' -tenant $Entry.TenantFilter -message "Baseline verification after the cache refresh failed to start: $($_.Exception.Message)" -Sev 'Error'
                }
            }
            return
        }

        # Every finished run re-verified state, so record today's fleet rollup for the
        # trend chart - even when nothing was remediated.
        try { Set-CIPPBaselineTrendPoint } catch {
            Write-Information "Baseline trend point skipped: $($_.Exception.Message)"
        }

        try { Send-CIPPBaselineAlertDigest } catch {
            Write-LogMessage -API 'Baselines' -message "Baseline alert digest failed: $($_.Exception.Message)" -Sev 'Error'
        }

        $Impacted = @{}
        $Verify = @{}
        foreach ($ActivityResult in @($Item.Results)) {
            foreach ($Record in @($ActivityResult)) {
                # Family types (IntuneDeviceConfigurations, ...) have no collector of their own; their umbrella cacheType refreshes them.
                if ($Record -and $Record.CacheType -and $Record.TenantFilter -and (Get-CIPPBaselineCommand -Name "Set-CIPPDBCache$($Record.CacheType)")) {
                    $Impacted[('{0}|{1}' -f $Record.TenantFilter, $Record.CacheType)] = $Record
                    if ($Record.Standard) {
                        $Verify[$Record.TenantFilter] ??= [System.Collections.Generic.HashSet[string]]::new()
                        $null = $Verify[$Record.TenantFilter].Add($Record.Standard)
                    }
                }
            }
        }
        # IntunePolicies also writes IntuneConfigurationPolicies, so collecting both reads every settings catalog policy twice.
        foreach ($Key in @($Impacted.Keys)) {
            if ($Key.EndsWith('|IntunePolicies')) { $Impacted.Remove(($Key -replace 'IntunePolicies$', 'IntuneConfigurationPolicies')) }
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
        $Orchestrator = @{
            Batch            = @($Batch)
            OrchestratorName = 'BaselineCacheRefresh'
            SkipLog          = $true
        }
        if ($Verify.Count -gt 0) {
            $Orchestrator.PostExecution = @{
                FunctionName = 'CIPPBaselineCacheRefresh'
                Parameters   = @{
                    RunId  = $Item.Parameters.RunId
                    Verify = @(foreach ($Tenant in @($Verify.Keys)) { @{ TenantFilter = $Tenant; Standards = @($Verify[$Tenant]) } })
                }
            }
        }
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]$Orchestrator)
        Write-LogMessage -API 'Baselines' -message "Baseline run finished - refreshing $($Impacted.Count) impacted cache(s)." -Sev 'Info'
    } catch {
        Write-LogMessage -API 'Baselines' -message "Baseline cache refresh failed: $($_.Exception.Message)" -Sev 'Error'
    }
}
