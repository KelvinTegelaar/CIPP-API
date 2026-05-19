
function New-CIPPStandardsRun {
    <#
    .SYNOPSIS
    Start the standards or drift run for a given tenant and template

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',
        [Parameter(Mandatory = $false)]
        [switch]$Force,
        [Parameter(Mandatory = $false)]
        $TemplateID,
        [Parameter(Mandatory = $false)]
        $runManually = $false,
        [Parameter(Mandatory = $false)]
        [switch]$Drift
    )
    # This is not called from the frontend but through a wrapper instead that manages the rbac
    Write-Information "Starting process for standards - $($tenantFilter). TemplateID: $($TemplateID) RunManually: $($runManually) Force: $($Force.IsPresent) Drift: $($Drift.IsPresent)"

    if ($Drift.IsPresent) {
        Write-Information 'Drift Standards Run'
        $AllTasks = Get-CIPPTenantAlignment | Where-Object -Property standardtype -EQ 'drift' | Select-Object -Property TenantFilter | Sort-Object -Unique -Property TenantFilter

        #For each item in our object, run the queue.
        $Queue = New-CippQueueEntry -Name 'Drift Standards' -TotalTasks ($AllTasks | Measure-Object).Count

        $Batch = foreach ($Task in $AllTasks) {
            [PSCustomObject]@{
                FunctionName = 'CIPPDriftManagement'
                Tenant       = $Task.TenantFilter
            }
        }

        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'DriftStandardsOrchestrator'
            Batch            = @($Batch)
            SkipLog          = $true
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started orchestration with ID = '$InstanceId' for drift standards run"
        #$Orchestrator = New-OrchestrationCheckStatusResponse -Request $Request -InstanceId $InstanceId
        return
    } else {
        Write-Information 'Classic Standards Run'

        if ($Force.IsPresent) {
            Write-Information 'Clearing Rerun Cache'
            Test-CIPPRerun -ClearAll -TenantFilter $TenantFilter -Type 'Standard'
        }

        $StandardsParams = @{
            TenantFilter = $TenantFilter
            runManually  = $runManually
        }
        if ($TemplateID) {
            $StandardsParams['TemplateId'] = $TemplateID
        }

        $AllTenantsList = Get-CIPPStandards @StandardsParams | Select-Object -ExpandProperty Tenant | Sort-Object -Unique

        # Build batch of per-tenant list activities
        $Batch = foreach ($Tenant in $AllTenantsList) {
            $BatchItem = @{
                FunctionName = 'CIPPStandardsList'
                TenantFilter = $Tenant
                runManually  = $runManually
            }
            if ($TemplateID) {
                $BatchItem['TemplateId'] = $TemplateID
            }
            $BatchItem
        }

        Write-Information "Built batch of $($Batch.Count) tenant standards list activities: $($Batch | ConvertTo-Json -Depth 5 -Compress)"

        # Start orchestrator with distributed batch and post-exec aggregation
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'StandardsList'
            Batch            = @($Batch)
            PostExecution    = @{
                FunctionName = 'CIPPStandardsApplyBatch'
            }
            SkipLog          = $true
        }

        Write-Information "InputObject: $($InputObject | ConvertTo-Json -Depth 5 -Compress)"
        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started standards list orchestration with ID = '$InstanceId'"
    }
}
