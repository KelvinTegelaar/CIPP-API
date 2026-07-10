function Push-AuditLogDownloadV2 {
    <#
    .SYNOPSIS
        Per-tenant audit-log download activity (V2). Polls created searches, downloads succeeded ones
        to CacheWebhooks, and advances the AuditLogCoverage ledger.
    .DESCRIPTION
        For the tenant's ledger rows in state 'Created' (and due):
          * bulk-poll Graph search status
          * succeeded  -> download records to CacheWebhooks, mark Downloaded (+ RecordCount)
          * failed     -> re-plan a fresh search (State = Planned, clear SearchId); dead-letter at cap
          * running/notStarted -> leave Created; if stuck > 4h, re-plan
          * download error -> increment Attempts + backoff; dead-letter at cap (NOT terminal)
        Returns a summary the PostExecution (AuditLogProcessV2) uses to decide whether to process.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $MaxAttempts = 6
    $StuckHours = 4
    $Downloaded = 0

    try {
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Now = (Get-Date).ToUniversalTime()
        $Rows = @(Get-CIPPAzDataTableEntity @Ledger -Filter "PartitionKey eq '$TenantFilter' and State eq 'Created'")
        $Rows = $Rows | Where-Object { -not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now }
        $Rows = @($Rows)
        if ($Rows.Count -eq 0) {
            return @{ TenantFilter = $TenantFilter; Success = $true; Downloaded = 0 }
        }

        # Bulk-poll Graph search status for this tenant's created searches
        $Requests = foreach ($Row in $Rows) {
            if ($Row.SearchId) { @{ id = [string]$Row.SearchId; url = "security/auditLog/queries/$($Row.SearchId)"; method = 'GET' } }
        }
        $Requests = @($Requests)
        $StatusById = @{}
        if ($Requests.Count -gt 0) {
            $Responses = New-GraphBulkRequest -Requests $Requests -AsApp $true -TenantId $TenantFilter
            foreach ($Response in $Responses) {
                if ($Response.body -and $Response.body.id) { $StatusById[[string]$Response.body.id] = [string]$Response.body.status }
            }
        }

        $CacheTable = Get-CippTable -TableName 'CacheWebhooks'

        foreach ($Row in $Rows) {
            $SearchId = [string]$Row.SearchId
            $Status = $StatusById[$SearchId]
            $CreatedAgeHours = if ($Row.CreatedUtc) { ($Now - ([datetimeoffset]$Row.CreatedUtc).UtcDateTime).TotalHours } else { 999 }

            if ($Status -eq 'succeeded') {
                try {
                    $Results = @(Get-CippAuditLogSearchResults -TenantFilter $TenantFilter -QueryId $SearchId)
                    foreach ($SearchResult in $Results) {
                        Add-CIPPAzDataTableEntity @CacheTable -Entity @{
                            RowKey                = [string]$SearchResult.id
                            PartitionKey          = [string]$TenantFilter
                            SearchId              = $SearchId
                            JSON                  = [string]($SearchResult | ConvertTo-Json -Depth 10 -Compress)
                            CippProcessing        = $false
                            CippProcessingStarted = ''
                        } -Force
                    }
                    $Downloaded += $Results.Count
                    # Empty windows have nothing to process - mark them Processed directly so they
                    # don't sit at Downloaded forever. Windows with records go to Downloaded and are
                    # advanced to Processed by Push-AuditLogTenantProcessV2 once their rows are drained.
                    $DownloadState = if ($Results.Count -eq 0) { 'Processed' } else { 'Downloaded' }
                    $LedgerUpdate = @{
                        PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = $DownloadState
                        RecordCount  = [int]$Results.Count; DownloadedUtc = $Now; Attempts = 0
                        SearchStatus = 'succeeded'; LastPolledUtc = $Now
                    }
                    if ($DownloadState -eq 'Processed') {
                        $LedgerUpdate.ProcessedUtc = $Now
                        $LedgerUpdate.MatchedCount = 0
                    }
                    Add-CIPPAzDataTableEntity @Ledger -Entity $LedgerUpdate -OperationType UpsertMerge
                    Write-Information "AuditLogV2: downloaded $($Results.Count) record(s) for $TenantFilter window $($Row.RowKey)"
                } catch {
                    $Attempts = [int]$Row.Attempts + 1
                    $RetryTotal = [int]$Row.RetryCount + 1
                    if ($Attempts -ge $MaxAttempts) {
                        Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'DeadLetter'; Attempts = $Attempts; RetryCount = $RetryTotal; LastError = [string]$_.Exception.Message; LastErrorUtc = $Now } -OperationType UpsertMerge
                    } else {
                        Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; Attempts = $Attempts; RetryCount = $RetryTotal; NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts $Attempts); LastError = [string]$_.Exception.Message; LastErrorUtc = $Now } -OperationType UpsertMerge
                    }
                    Write-Information "AuditLogV2: download error for $TenantFilter window $($Row.RowKey): $($_.Exception.Message)"
                }
            } elseif ($Status -eq 'failed') {
                $Attempts = [int]$Row.Attempts + 1
                $RetryTotal = [int]$Row.RetryCount + 1
                if ($Attempts -ge $MaxAttempts) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'DeadLetter'; Attempts = $Attempts; RetryCount = $RetryTotal; SearchStatus = 'failed'; LastPolledUtc = $Now; LastError = 'Graph search failed'; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; SearchId = ''; Attempts = $Attempts; RetryCount = $RetryTotal; SearchStatus = ''; LastPolledUtc = $Now; NextAttemptUtc = (Get-CippAuditLogNextAttempt -Attempts $Attempts); LastError = 'Graph search failed; re-planning'; LastErrorUtc = $Now } -OperationType UpsertMerge
                }
            } elseif ($Status -in @('running', 'notStarted')) {
                if ($CreatedAgeHours -ge $StuckHours) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; SearchId = ''; SearchStatus = ''; LastPolledUtc = $Now; RetryCount = ([int]$Row.RetryCount + 1); LastError = 'Search stuck; re-planning'; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    # Not ready yet: leave Created, but persist the live Graph search status so a pending
                    # window shows WHY it is still in-flight (e.g. 'running') rather than looking stuck.
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; SearchStatus = [string]$Status; LastPolledUtc = $Now } -OperationType UpsertMerge
                }
            } else {
                # Unknown / search no longer present on Graph
                if ($CreatedAgeHours -ge $StuckHours) {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; State = 'Planned'; SearchId = ''; SearchStatus = ''; LastPolledUtc = $Now; RetryCount = ([int]$Row.RetryCount + 1); LastError = 'Search not found; re-planning'; LastErrorUtc = $Now } -OperationType UpsertMerge
                } else {
                    Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $TenantFilter; RowKey = $Row.RowKey; SearchStatus = $(if ($Status) { [string]$Status } else { 'unknown' }); LastPolledUtc = $Now } -OperationType UpsertMerge
                }
            }
        }

        return @{ TenantFilter = $TenantFilter; Success = $true; Downloaded = $Downloaded }
    } catch {
        Write-Information ('Push-AuditLogDownloadV2 error for {0}: {1}' -f $TenantFilter, $_.Exception.Message)
        return @{ TenantFilter = $TenantFilter; Success = $false; Downloaded = $Downloaded; Error = $_.Exception.Message }
    }
}
