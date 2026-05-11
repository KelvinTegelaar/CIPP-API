function Start-CIPPDBTestsRun {
    <#
    .SYNOPSIS
    Start the Tests run orchestration

    .DESCRIPTION
    Builds tenant test-list activities and starts the two-phase tests orchestration.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter = 'allTenants',

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    Write-Information "Starting tests run for tenant: $TenantFilter"

    $RerunParams = @{
        TenantFilter = $TenantFilter
        Type         = 'CippTests'
        API          = 'CippTests'
    }

    if ($Force) {
        Write-Information 'Force flag set, clearing rerun protection'
        Test-CIPPRerun @RerunParams -Clear | Out-Null
    }

    $Rerun = Test-CIPPRerun @RerunParams
    if ($Rerun -eq $true) {
        Write-Information "Rerun protection prevented test run for $TenantFilter"
        return $true
    }

    try {
        $AllTenantsList = if ($TenantFilter -eq 'allTenants') {
            $DbCounts = Get-CIPPDbItem -CountsOnly -TenantFilter 'allTenants'
            $TenantsWithData = $DbCounts | Where-Object { (($_.DataCount ?? $_.Count) ?? 0) -gt 0 } | Select-Object -ExpandProperty PartitionKey -Unique
            Write-Information "Found $($TenantsWithData.Count) tenants with data in database"
            $TenantsWithData
        } else {
            $DbCounts = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly
            if ((($DbCounts | Measure-Object -Property DataCount -Sum).Sum ?? 0) -gt 0) {
                @($TenantFilter)
            } else {
                Write-LogMessage -API 'Tests' -tenant $TenantFilter -message 'Tenant has no data in database. Skipping tests.' -sev Info
                @()
            }
        }

        if ($AllTenantsList.Count -eq 0) {
            Write-LogMessage -API 'Tests' -message 'No tenants with data found. Exiting.' -sev Info
            return
        }

        # Phase 1: Build per-tenant list activities (discover tests per tenant)
        $Batch = foreach ($Tenant in $AllTenantsList) {
            @{
                FunctionName = 'CIPPTestsList'
                TenantFilter = $Tenant
            }
        }

        Write-Information "Built batch of $($Batch.Count) tenant test list activities"

        # Phase 2 via PostExecution: Aggregate all task lists and start flat execution orchestrator
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'TestsList'
            Batch            = @($Batch)
            SkipLog          = $true
            PostExecution    = @{
                FunctionName = 'CIPPTestsApplyBatch'
            }
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        Write-Information "Started tests list orchestration with ID = '$InstanceId'"

        return @{
            InstanceId = $InstanceId
            Message    = "Tests orchestration started: $($AllTenantsList.Count) tenant orchestrators will be created"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -message "Failed to start tests orchestration: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw $ErrorMessage
    }
}
