function Start-CIPPDBCacheOrchestrator {
    <#
    .SYNOPSIS
        Orchestrates database cache collection across all tenants

    .DESCRIPTION
        Creates per-tenant jobs to collect and cache Microsoft Graph data

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

        $TaskCount = $TenantList.Count

        $Queue = New-CippQueueEntry -Name 'Database Cache Collection' -TotalTasks $TaskCount
        $Batch = [system.collections.generic.list[object]]::new()
        foreach ($Tenant in $TenantList) {
            $Batch.Add([PSCustomObject]@{
                    FunctionName = 'CIPPDBCacheData'
                    TenantFilter = $Tenant.defaultDomainName
                    QueueId      = $Queue.RowKey
                    QueueName    = "DB Cache - $($Tenant.defaultDomainName)"
                })
        }
        Write-Host "Created queue $($Queue.RowKey) for database cache collection of $($TenantList.Count) tenants"
        Write-Host "Starting batch of $($Batch.Count) cache collection activities"
        $InputObject = [PSCustomObject]@{
            Batch            = @($Batch)
            OrchestratorName = 'CIPPDBCacheOrchestrator'
            SkipLog          = $false
        }

        Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

        Write-LogMessage -API 'CIPPDBCache' -message "Queued database cache collection for $($TenantList.Count) tenants" -sev Info

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -message "Failed to start orchestration: $($_.Exception.Message)" -sev Error
        throw
    }
}
