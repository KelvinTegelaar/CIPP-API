function Push-CIPPDBCacheApplyBatch {
    <#
    .SYNOPSIS
        Aggregate cache tasks from all tenants and start a flat execution orchestrator (Phase 2)

    .DESCRIPTION
        PostExecution function for the DBCache pipeline. Receives aggregated results from the
        per-tenant CIPPDBCacheData list activities, flattens them into a single batch, and starts
        one orchestrator to execute all cache collection tasks across all tenants in parallel.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        # Aggregate all cache tasks from all tenant list activities
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
            Write-Information 'No cache tasks to execute across all tenants'
            return @{ Success = $true; TaskCount = 0 }
        }

        Write-Information "Aggregated $($AllTasks.Count) cache tasks from all tenants"

        # Start a single flat orchestrator to execute all cache tasks
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'CIPPDBCacheExecute'
            Batch            = @($AllTasks)
            SkipLog          = $true
        }

        # Add test run post-execution if flagged
        if ($Item.Parameters -and $Item.Parameters.TestRun -eq $true -and $Item.Parameters.TenantFilter) {
            $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
                FunctionName = 'CIPPDBTestsRun'
                Parameters   = @{
                    TenantFilter = $Item.Parameters.TenantFilter
                }
            }
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 10 -Compress)
        Write-Information "Started flat cache execution orchestrator with ID = '$InstanceId' for $($AllTasks.Count) tasks"

        return @{
            Success    = $true
            TaskCount  = $AllTasks.Count
            InstanceId = $InstanceId
        }

    } catch {
        Write-Warning "Error in DBCache apply batch aggregation: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
