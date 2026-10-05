function Push-CIPPTestsApplyBatch {
    <#
    .SYNOPSIS
        Aggregate test tasks from all tenants and start one sequential execution orchestrator per tenant (Phase 2)

    .DESCRIPTION
        PostExecution function for the Tests pipeline. Receives aggregated results from the
        per-tenant CIPPTestsList activities and starts one sequential orchestrator per tenant, so
        tenants run in parallel while each tenant's suites run one at a time on one worker.

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
        $TenantGroups = [ordered]@{}
        foreach ($Task in $AllTasks) {
            $Tenant = [string]$Task.TenantFilter
            if (-not $TenantGroups.Contains($Tenant)) { $TenantGroups[$Tenant] = [System.Collections.Generic.List[object]]::new() }
            $TenantGroups[$Tenant].Add($Task)
        }

        # One sequential run per tenant: its suites share the tenant's cached data instead of parsing it concurrently
        $InstanceIds = foreach ($Tenant in $TenantGroups.Keys) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = if ($TenantGroups.Count -gt 1) { "CIPPTestsExecute$TenantSuffix-$Tenant" } else { "CIPPTestsExecute$TenantSuffix" }
                Batch            = @($TenantGroups[$Tenant])
                Sequential       = $true
                DurableMode      = 'Sequence'
                SkipLog          = $true
            }
            Start-CIPPOrchestrator -InputObject $InputObject
        }
        Write-Information "Started $(@($InstanceIds).Count) sequential tests execution orchestrators for $($AllTasks.Count) tasks"

        return @{
            Success    = $true
            TaskCount  = $AllTasks.Count
            InstanceId = @($InstanceIds)
        }

    } catch {
        Write-Warning "Error in Tests apply batch aggregation: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
