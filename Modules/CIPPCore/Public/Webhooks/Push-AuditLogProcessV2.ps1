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
        # Gate on the LEDGER, not the cache. CacheWebhooks is partitioned per search
        # (tenant|searchId), so there is no single partition to count for a tenant, and a
        # cross-partition scan just to answer "is there anything to do" would reintroduce exactly
        # the cost the layout removes. The ledger tracks the same state and is keyed by tenant.
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Pending = @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantFilter' and (State eq 'Downloaded' or State eq 'Processing')" -Property @('PartitionKey', 'RowKey'))
        if ($Pending.Count -eq 0) {
            Write-Information "AuditLogProcessV2: no searches awaiting processing for $TenantFilter"
            return @{ Success = $true; Processed = $false }
        }

        Write-Information "AuditLogProcessV2: enqueueing processing for $TenantFilter ($($Pending.Count) search(es) pending)"
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
