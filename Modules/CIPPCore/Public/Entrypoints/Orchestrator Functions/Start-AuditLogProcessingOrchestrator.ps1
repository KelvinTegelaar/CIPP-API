function Start-AuditLogProcessingOrchestrator {
    <#
    .SYNOPSIS
    Start the Audit Log Processing Orchestrator

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-Information 'Starting audit log processing in batches of 1000, per tenant'
    $WebhookCacheTable = Get-CippTable -TableName 'CacheWebhooks'

    $DataTableQuery = @{
        First = 20000
        Skip  = 0
    }

    do {
        $WebhookCache = Get-CIPPAzDataTableEntity @WebhookCacheTable @DataTableQuery
        $TenantGroups = $WebhookCache | Group-Object -Property PartitionKey

        if ($TenantGroups) {
            Write-Information "Processing webhook cache for $($TenantGroups.Count) tenants"
            #Write-Warning "AuditLogJobs are: $($TenantGroups.Count) tenants. Tenants: $($TenantGroups.name | ConvertTo-Json -Compress) "
            #Write-Warning "Here are the groups: $($TenantGroups | ConvertTo-Json -Compress)"
            $ProcessQueue = New-CippQueueEntry -Name 'Audit Logs Process' -Reference 'AuditLogsProcess' -TotalTasks ($TenantGroups | Measure-Object -Property Count -Sum).Sum
            $ProcessBatch = foreach ($TenantGroup in $TenantGroups) {
                $TenantFilter = $TenantGroup.Name
                $RowIds = @($TenantGroup.Group.RowKey)
                for ($i = 0; $i -lt $RowIds.Count; $i += 1000) {
                    Write-Host "Processing $TenantFilter with $($RowIds.Count) row IDs. We're processing id $($RowIds[$i]) to $($RowIds[[Math]::Min($i + 999, $RowIds.Count - 1)])"
                    $BatchRowIds = $RowIds[$i..([Math]::Min($i + 999, $RowIds.Count - 1))]
                    [PSCustomObject]@{
                        TenantFilter = $TenantFilter
                        RowIds       = $BatchRowIds
                        QueueId      = $ProcessQueue.RowKey
                        FunctionName = 'AuditLogTenantProcess'
                    }
                }
            }
            if ($ProcessBatch) {
                $ProcessInputObject = [PSCustomObject]@{
                    OrchestratorName = 'AuditLogTenantProcess'
                    Batch            = @($ProcessBatch)
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($ProcessInputObject | ConvertTo-Json -Depth 5 -Compress)
                Write-Information "Started audit log processing orchestration with $($ProcessBatch.Count) batches"
            }
        }

        if ($WebhookCache.Count -lt 20000) {
            Write-Information 'No more rows to process'
            break
        }
        Write-Information "Processed $($WebhookCache.Count) rows"
        $DataTableQuery.Skip += 20000
        Write-Information "Getting next batch of $($DataTableQuery.First) rows"
    } while ($WebhookCache.Count -eq 20000)
}
