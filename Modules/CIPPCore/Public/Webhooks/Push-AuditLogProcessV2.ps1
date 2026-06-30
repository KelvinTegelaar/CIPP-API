function Push-AuditLogProcessV2 {
    <#
    .SYNOPSIS
        PostExecution step of the V2 ingestion orchestrator. If the per-tenant download succeeded,
        enqueues a per-tenant processing orchestrator (post-exec style).
    .DESCRIPTION
        Receives the download orchestrator's aggregated results ($Item.Results) and the tenant filter
        ($Item.Parameters.TenantFilter). When at least one record was downloaded, it starts a
        per-tenant processing orchestrator whose QueueFunction (AuditLogProcessingBatchV2) pages that
        tenant's CacheWebhooks rows into batches handled by the existing AuditLogTenantProcess engine.
        If nothing was downloaded, processing is skipped.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    try {
        $TenantFilter = $Item.Parameters.TenantFilter
        if (-not $TenantFilter) {
            $TenantFilter = (@($Item.Results) | Where-Object { $_.TenantFilter } | Select-Object -First 1).TenantFilter
        }
        if (-not $TenantFilter) {
            Write-Information 'AuditLogProcessV2: no tenant filter resolved; skipping'
            return @{ Success = $false }
        }

        # Fire processing whenever the tenant has rows pending in the cache - records just downloaded
        # this cycle OR rows left behind by an earlier crash. Not gated on the download count, so a
        # crashed/partial processing run is retried on the next cycle. The batch builder is the
        # authoritative gate (claims claimable rows; returns nothing if there's truly no work).
        $CacheTable = Get-CippTable -TableName 'CacheWebhooks'
        $Pending = @(Get-CIPPAzDataTableEntity @CacheTable -Filter "PartitionKey eq '$TenantFilter'" -Property @('PartitionKey', 'RowKey'))
        if ($Pending.Count -eq 0) {
            Write-Information "AuditLogProcessV2: no pending cache rows for $TenantFilter; nothing to process"
            return @{ Success = $true; Processed = $false }
        }

        Write-Information "AuditLogProcessV2: enqueueing processing for $TenantFilter ($($Pending.Count) pending cache row(s))"
        $InputObject = [PSCustomObject]@{
            OrchestratorName = "AuditLogProcessV2-$TenantFilter"
            QueueFunction    = [PSCustomObject]@{
                FunctionName = 'AuditLogProcessingBatchV2'
                Parameters   = @{ TenantFilter = $TenantFilter }
            }
            SkipLog          = $true
        }
        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
        return @{ Success = $true; Processed = $true; InstanceId = $InstanceId }
    } catch {
        Write-Information ('Push-AuditLogProcessV2 error: {0}' -f $_.Exception.Message)
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
