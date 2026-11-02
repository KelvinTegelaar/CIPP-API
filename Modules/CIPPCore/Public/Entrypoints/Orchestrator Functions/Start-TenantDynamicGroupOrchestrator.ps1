function Start-TenantDynamicGroupOrchestrator {
    <#
    .SYNOPSIS
    Start the Tenant Dynamic Group Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$GroupId = 'All'
    )

    try {
        Write-Information 'Updating Dynamic Tenant Groups'
        $TenantGroups = @{
            Dynamic = $true
        }
        $TenantGroups = Get-TenantGroups @TenantGroups
        if ($GroupId -ne 'All') {
            $TenantGroups = $TenantGroups | Where-Object { $_.Id -eq $GroupId }
        }

        if ($TenantGroups.Count -gt 0) {
            Write-Information "Found $($TenantGroups.Count) dynamic tenant groups"
            $Queue = New-CippQueueEntry -Name 'Dynamic Tenant Groups' -TotalTasks 1
            # One task for all groups, so tenants and licences are loaded once rather than per group
            $TenantBatch = [PSCustomObject]@{
                Name         = if ($GroupId -eq 'All') { 'All dynamic groups' } else { $TenantGroups.Name }
                Id           = if ($GroupId -ne 'All') { $GroupId }
                FunctionName = 'UpdateDynamicTenantGroup'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'UpdateDynamicTenantGroups'
                AllowCollision   = $GroupId -ne 'All'
                Batch            = @($TenantBatch)
                SkipLog          = $true
            }
            if ($PSCmdlet.ShouldProcess('Start-TenantDynamicGroupOrchestrator', 'Starting Tenant Dynamic Group Orchestrator')) {
                Start-CIPPOrchestrator -InputObject $InputObject
            }
        } else {
            Write-Information 'No tenants require permissions update'
        }
    } catch {}
}
