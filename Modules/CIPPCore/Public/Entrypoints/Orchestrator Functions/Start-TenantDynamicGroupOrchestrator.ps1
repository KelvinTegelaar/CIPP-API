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
            $Queue = New-CippQueueEntry -Name 'Dynamic Tenant Groups' -TotalTasks $TenantGroups.Count
            $TenantBatch = $TenantGroups | Select-Object Name, Id, @{n = 'FunctionName'; exp = { 'UpdateDynamicTenantGroup' } }, @{n = 'QueueId'; exp = { $Queue.RowKey } }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'UpdateDynamicTenantGroups'
                Batch            = @($TenantBatch)
                SkipLog          = $true
            }
            if ($PSCmdlet.ShouldProcess('Start-TenantDynamicGroupOrchestrator', 'Starting Tenant Dynamic Group Orchestrator')) {
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            }
        } else {
            Write-Information 'No tenants require permissions update'
        }
    } catch {}
}
