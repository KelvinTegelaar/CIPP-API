function Push-CIPPDBCacheApplyBatch {
    <#
    .SYNOPSIS
        Aggregate cache tasks from all tenants and start the execution orchestrators (Phase 2)

    .DESCRIPTION
        PostExecution function for the DBCache pipeline. Receives aggregated results from the
        per-tenant CIPPDBCacheData list activities and starts one execution run per tenant, each
        running at most two of that tenant's collection groups at once, for a nightly or a
        single-tenant refresh alike.

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

        # A test run chains the tests after its tenant's run, so Intune stays in that run and the tests wait for it.
        $TestRun = $Item.Parameters.TestRun -eq $true -and $Item.Parameters.TenantFilter

        # Intune runs a band ahead so it reads the report exports before their downloads expire
        if (-not $TestRun) {
            $IntuneTasks = @($AllTasks | Where-Object { $_.CollectionType -eq 'Intune' })
            if ($IntuneTasks.Count -gt 0) {
                $OpContext = Get-Variable -Name 'CraftOperationContext' -Scope Global -ValueOnly -ErrorAction SilentlyContinue
                $IntunePriority = [math]::Max(0, (Resolve-CIPPOrchestratorPriority -InputObject $null -OpContext $OpContext) - 1)
                $IntuneId = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                        OrchestratorName = 'CIPPDBCacheExecuteIntune'
                        AllowCollision   = $false
                        Batch            = $IntuneTasks
                        Priority         = $IntunePriority
                        SkipLog          = $true
                    })
                Write-Information "Started Intune cache execution orchestrator with ID = '$IntuneId' for $($IntuneTasks.Count) tasks at P$IntunePriority"
                $AllTasks = [System.Collections.Generic.List[object]]@($AllTasks | Where-Object { $_.CollectionType -ne 'Intune' })
                if ($AllTasks.Count -eq 0) { return @{ Success = $true; TaskCount = $IntuneTasks.Count; InstanceId = $IntuneId } }
            }
        }

        $TenantGroups = [ordered]@{}
        foreach ($Task in $AllTasks) {
            $Tenant = [string]$Task.TenantFilter
            if (-not $TenantGroups.Contains($Tenant)) { $TenantGroups[$Tenant] = [System.Collections.Generic.List[object]]::new() }
            $TenantGroups[$Tenant].Add($Task)
        }

        # One run per tenant, capped, so the background slots spread across tenants instead of
        # several collection groups hitting the same tenant's Graph/EXO/SPO budget at once.
        $InstanceId = foreach ($Tenant in $TenantGroups.Keys) {
            $InputObject = [PSCustomObject]@{
                OrchestratorName = "CIPPDBCacheExecute-$Tenant"
                AllowCollision   = $false
                Batch            = @($TenantGroups[$Tenant])
                MaxConcurrency   = 2
                SkipLog          = $true
            }
            if ($TestRun) {
                $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
                    FunctionName = 'CIPPDBTestsRun'
                    Parameters   = @{ TenantFilter = $Tenant }
                }
            }
            Start-CIPPOrchestrator -InputObject $InputObject
        }
        Write-Information "Started $(@($InstanceId).Count) per-tenant cache execution orchestrators for $($AllTasks.Count) tasks"

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
