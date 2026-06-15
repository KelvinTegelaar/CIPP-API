function Start-CIPPDBCacheOrchestrator {
    <#
    .SYNOPSIS
        Orchestrates database cache collection across all tenants

    .DESCRIPTION
        Uses a two-phase fan-out/fan-in pattern (matching Standards):
        Phase 1: Fan out CIPPDBCacheData activities per tenant to check licenses and build task lists
        Phase 2: PostExecution aggregates all tasks and starts a single flat orchestrator to execute them

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param()

    try {
        Write-LogMessage -API 'CIPPDBCache' -message 'Starting database cache orchestration' -sev Info
        Write-Host 'Starting database cache orchestration'
        $TenantList = Get-Tenants | Where-Object { $_.defaultDomainName -ne $null }

        if ($TenantList.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -message 'No tenants found for cache collection' -sev Warning
            return
        }

        $Queue = New-CippQueueEntry -Name 'Database Cache Collection' -TotalTasks $TenantList.Count

        # Phase 1: Build per-tenant list activities (license check + task list generation)
        $Batch = foreach ($Tenant in $TenantList) {
            [PSCustomObject]@{
                FunctionName = 'CIPPDBCacheData'
                TenantFilter = $Tenant.defaultDomainName
                QueueId      = $Queue.RowKey
                QueueName    = "DB Cache - $($Tenant.defaultDomainName)"
            }
        }

        Write-Host "Created queue $($Queue.RowKey) for database cache collection of $($TenantList.Count) tenants"

        # Phase 2 via PostExecution: Aggregate all task lists and start flat execution orchestrator
        $InputObject = [PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = 'CIPPDBCacheOrchestrator'
            SkipLog          = $false
            PostExecution    = @{
                FunctionName = 'CIPPDBCacheApplyBatch'
            }
        }

        Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -API 'CIPPDBCache' -message "Queued database cache collection for $($TenantList.Count) tenants" -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -message "Failed to start orchestration: $($_.Exception.Message)" -sev Error
        throw
    }
}
