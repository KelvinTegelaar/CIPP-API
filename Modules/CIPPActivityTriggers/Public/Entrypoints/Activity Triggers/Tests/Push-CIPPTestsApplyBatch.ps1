function Push-CIPPTestsApplyBatch {
    <#
    .SYNOPSIS
        Aggregate test tasks from all tenants and start a flat execution orchestrator (Phase 2)

    .DESCRIPTION
        PostExecution function for the Tests pipeline. Receives aggregated results from the
        per-tenant CIPPTestsList activities, flattens them into a single batch, and starts
        one orchestrator to execute all test tasks across all tenants in parallel.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        # Aggregate all test tasks from all tenant list activities
        $AllTasks = [System.Collections.Generic.List[object]]::new()

        foreach ($TenantResult in $Item.Results) {
            foreach ($Batch in $TenantResult) {
                foreach ($Task in $Batch) {
                    if ($Task -and $Task.FunctionName) {
                        $AllTasks.Add($Task)
                    }
                }
            }
        }

        if ($AllTasks.Count -eq 0) {
            Write-Information 'No test tasks to execute across all tenants'
            return @{ Success = $true; TaskCount = 0 }
        }

        Write-Information "Aggregated $($AllTasks.Count) test tasks from all tenants"

        # Start a single flat orchestrator to execute all test tasks
        $TenantSuffix = if ($Item.Parameters.TenantFilter) { "_$($Item.Parameters.TenantFilter)" } else { '' }
        $InputObject = [PSCustomObject]@{
            OrchestratorName = "CIPPTestsExecute$TenantSuffix"
            Batch            = @($AllTasks)
            SkipLog          = $true
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started flat tests execution orchestrator with ID = '$InstanceId' for $($AllTasks.Count) tasks"

        return @{
            Success    = $true
            TaskCount  = $AllTasks.Count
            InstanceId = $InstanceId
        }

    } catch {
        Write-Warning "Error in Tests apply batch aggregation: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
