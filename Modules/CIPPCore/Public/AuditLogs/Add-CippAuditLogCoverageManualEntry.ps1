function Add-CippAuditLogCoverageManualEntry {
    <#
    .SYNOPSIS
        Bridge a manually-created audit log search into the V2 AuditLogCoverage ledger so the
        pipeline downloads and processes it automatically (Option B).
    .DESCRIPTION
        Manual searches live in the AuditLogSearches table, which the (now V2-only) pipeline no
        longer scans. When alert processing is requested for a manual search, this writes a ledger
        row keyed 'MANUAL-<searchId>' in State 'Created' so Start-AuditLogIngestionV2 /
        Push-AuditLogDownloadV2 poll, download and process it like any other search - it inherits
        retries, the orphan sweep, SearchStatus tracking and the coverage UI.

        The RowKey prefix keeps these out of the window planner: Get-CippAuditLogPlannedWindows only
        considers 14-digit RowKeys and Get-CippAuditLogReconciliationWindows only 'RECON-*', so a
        'MANUAL-*' row is never treated as a window, gap or reconciliation block. Type 'Manual' lets
        the UI exclude them from the window heatmap/charts.

        Idempotent (UpsertMerge): re-queuing the same search resets State to 'Created' to reprocess.
    .PARAMETER TenantFilter
        Tenant default domain (becomes the ledger PartitionKey).
    .PARAMETER SearchId
        The Graph audit-log search id.
    .PARAMETER StartTime
        Search start (datetime / DateTimeOffset / ISO string). Stored as WindowStart.
    .PARAMETER EndTime
        Search end. Stored as WindowEnd.
    .PARAMETER SearchStatus
        Graph search status at creation (e.g. notStarted); refreshed on each poll.
    .PARAMETER TenantId
        Tenant customerId. Resolved from TenantFilter if not supplied.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$SearchId,
        $StartTime,
        $EndTime,
        [string]$SearchStatus,
        [string]$TenantId
    )

    try {
        if (-not $TenantId) {
            try { $TenantId = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1 -ExpandProperty customerId } catch {}
        }

        $Now = (Get-Date).ToUniversalTime()
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Entity = @{
            PartitionKey  = [string]$TenantFilter
            RowKey        = 'MANUAL-' + [string]$SearchId
            TenantId      = [string]$TenantId
            Type          = 'Manual'
            State         = 'Created'
            SearchId      = [string]$SearchId
            SearchStatus  = [string]$SearchStatus
            Attempts      = 0
            RetryCount    = 0
            ThrottleCount = 0
            CreatedUtc    = $Now
            LastPolledUtc = $Now
            LastError     = ''
        }
        if ($StartTime) { try { $Entity.WindowStart = ([datetimeoffset]$StartTime).UtcDateTime } catch {} }
        if ($EndTime) { try { $Entity.WindowEnd = ([datetimeoffset]$EndTime).UtcDateTime } catch {} }

        Add-CIPPAzDataTableEntity @Ledger -Entity $Entity -OperationType UpsertMerge
        Write-Information "AuditLogV2: bridged manual search $SearchId for $TenantFilter into coverage ledger (MANUAL-$SearchId)"
    } catch {
        Write-Information ('Add-CippAuditLogCoverageManualEntry error for {0} / {1}: {2}' -f $TenantFilter, $SearchId, $_.Exception.Message)
    }
}
